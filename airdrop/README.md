# Base → BNB Chain certificate re-issue (补铸) runbook

WTF Academy is migrating its SBT certificates from Base (chain 8453) to BNB Chain (chain 56).
Everyone who held a certificate on Base must be re-issued the same certificate on BSC.

| | |
| --- | --- |
| Legacy SBT on Base | `0xB05D424943350aDfadeC4731CD54f12cC45E8c5c` |
| Legacy Minter on Base | `0x2BBE57dA6DFE615B9cE86B2BD149A953af7385d2` (signature gate, **not** the SBT) |
| Base SBT deploy block | `15708166` |
| New SBT on BSC | deployed by `script/Deploy.s.sol` — record the address |

Two moving parts:

- `script/export-base-holders.sh` — replays Base transfer logs into `airdrop/base-holders.json`.
- `script/Airdrop.s.sol` — calls `WTFSBT1155.batchMint` on BSC in chunks.

---

## ⚠️ soulIds must line up

The exported `soulIds` are **Base** ids. On BNB Chain, `soulId` is assigned implicitly by the
order of `createSoul()` calls (`latestUnusedTokenId` increments by one each time). If you
create the souls on BSC in a different order than on Base, the airdrop will hand people the
**wrong certificate**, and the only remedy is burning and re-minting.

Two safe options — pick one *before* running the airdrop:

1. **Preferred:** call `createSoul()` on BSC in the exact same order as on Base, so Base
   `soulId == BSC soulId`. Verify with `getSoulName(i)` on both chains.
2. **Remap:** set `SOUL_ID_MAP` on the airdrop script, a flat JSON object of decimal-string
   old→new ids. Unlisted ids pass through unchanged.

   ```bash
   export SOUL_ID_MAP='{"0":"3","1":"4"}'   # Base soul 0 -> BSC soul 3, Base 1 -> BSC 4
   ```

The airdrop script also refuses to run if any (post-remap) `soulId >= latestUnusedTokenId`
on the target chain, so a missing `createSoul()` is caught before any transaction is sent.
It cannot, however, detect a *wrong but existing* id — that is what step 1 or 2 is for.

---

## Step 1 — export the holder set from Base

```bash
cd <repo root>
./script/export-base-holders.sh --dry-run     # summary only, writes nothing
./script/export-base-holders.sh               # writes airdrop/base-holders.json
```

Requires `cast` and `jq`. Environment variables (all optional, documented in the script
header): `BASE_RPC_URL`, `BASE_SBT_ADDRESS`, `BASE_START_BLOCK`, `BASE_END_BLOCK`,
`BLOCK_CHUNK`, `PARALLEL`, `OUT_FILE`, `CACHE_DIR`.

The public Base RPC caps `eth_getLogs` at a 10,000-block range, so the full history is
~3,400 requests. Per-chunk responses are cached under `airdrop/.cache/base-logs/`, so an
interrupted run resumes cheaply; delete the directory to force a fresh scan. A private RPC
with a larger range limit (raise `BLOCK_CHUNK`) is much faster.

## Step 2 — review the JSON

```bash
jq '{count, fromBlock, toBlock, sourceContract}' airdrop/base-holders.json
jq -r '.soulIds | group_by(.) | map({soulId: .[0], holders: length})' airdrop/base-holders.json
```

Cross-check against the chain — the per-soul holder count must equal `totalSupply(soulId)`
on Base (assuming nothing was burned):

```bash
cast call 0xB05D424943350aDfadeC4731CD54f12cC45E8c5c "totalSupply(uint256)(uint256)" 0 \
  --rpc-url https://mainnet.base.org
```

Also confirm there are no duplicate `(recipient, soulId)` pairs and no zero addresses:

```bash
jq -r '[.recipients, .soulIds] | transpose | map(join(":")) | (length) as $n
       | {entries: $n, unique: (unique | length)}' airdrop/base-holders.json
```

## Step 3 — grant the airdrop EOA the minter role

The broadcasting EOA must be a minter. As the **contract owner** on BSC:

```bash
cast send $SBT_ADDRESS "addMinter(address)" $AIRDROP_EOA \
  --rpc-url bsc --private-key $OWNER_KEY
cast call $SBT_ADDRESS "isMinter(address)(bool)" $AIRDROP_EOA --rpc-url bsc
```

The airdrop script's preflight reverts with an explicit instruction if this is skipped.

## Step 4 — dry run, then testnet, then mainnet

Simulate (no transactions, no `--broadcast`):

```bash
SBT_ADDRESS=0x... forge script script/Airdrop.s.sol --rpc-url bsc_testnet
```

Testnet broadcast — do a full rehearsal against a testnet deployment first:

```bash
SBT_ADDRESS=0x... forge script script/Airdrop.s.sol \
  --rpc-url bsc_testnet --broadcast --private-key $AIRDROP_KEY
```

Mainnet broadcast (`--slow` sends transactions one at a time, which avoids nonce races and
makes a partial failure easy to resume):

```bash
SBT_ADDRESS=0x... CHUNK_SIZE=100 forge script script/Airdrop.s.sol \
  --rpc-url bsc --broadcast --slow --private-key $AIRDROP_KEY
```

Environment variables:

| var | default | meaning |
| --- | --- | --- |
| `SBT_ADDRESS` | *required* | deployed `WTFSBT1155` on BNB Chain |
| `HOLDERS_FILE` | `airdrop/base-holders.json` | input file |
| `CHUNK_SIZE` | `100` | entries per `batchMint` call |
| `SOUL_ID_MAP` | *unset* | Base→BSC soulId remap, see above |

`batchMint` **skips recipients that already hold the soul**, so re-running the script after a
partial failure is safe and idempotent — it will only mint what is still missing.

Gas: **~3.39M gas per 100-entry chunk** of all-new recipients (~34k per certificate), measured
from real receipts on a local anvil run of the full 204-entry Base export (3,393,271 /
3,355,739 / 176,532 for chunks of 100 / 100 / 4). A re-run over already-minted entries costs
almost nothing because the script skips whole chunks. BNB Chain's block gas limit is far above
this, so `CHUNK_SIZE=100` is comfortable; raise it only after measuring.

## Step 5 — revoke the minter role

```bash
cast send $SBT_ADDRESS "removeMinter(address)" $AIRDROP_EOA \
  --rpc-url bsc --private-key $OWNER_KEY
cast call $SBT_ADDRESS "isMinter(address)(bool)" $AIRDROP_EOA --rpc-url bsc   # -> false
```

Do not leave the airdrop EOA as a minter. A minter can mint arbitrary certificates and, via
`_update`, move soulbound tokens between addresses.

## Step 6 — verify balances

Re-run the airdrop script **without** `--broadcast`; a clean run reports
`newly minted: 0`, meaning every entry is now held on BSC:

```bash
SBT_ADDRESS=0x... forge script script/Airdrop.s.sol --rpc-url bsc
```

Spot-check supplies and individual holders:

```bash
cast call $SBT_ADDRESS "totalSupply(uint256)(uint256)" 0 --rpc-url bsc
cast call $SBT_ADDRESS "balanceOf(address,uint256)(uint256)" $SOME_HOLDER 0 --rpc-url bsc
```

---

## Input file format

`airdrop/base-holders.example.json` is a working sample. Two parallel arrays — entry `i` means
"mint one of `soulIds[i]` to `recipients[i]`". The remaining fields are provenance metadata for
humans and are not read by the script.

```json
{
  "sourceChainId": 8453,
  "sourceContract": "0xB05D424943350aDfadeC4731CD54f12cC45E8c5c",
  "fromBlock": 15708166,
  "toBlock": 49143677,
  "count": 5,
  "recipients": ["0x11346aa1...", "0x36390b9b...", "..."],
  "soulIds": [0, 0, 0, 1, 1]
}
```

`recipients` are lowercase hex addresses; `soulIds` are JSON numbers. A hand-written file works
fine as long as the two arrays are the same length.
