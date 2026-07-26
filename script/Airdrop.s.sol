// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/WTFSBT1155.sol";

/**
 * @notice Re-issues ("补铸") the legacy Base certificates on BNB Chain by calling
 *         WTFSBT1155.batchMint in chunks that stay well under the block gas limit.
 *
 * Input file (produced by script/export-base-holders.sh), two parallel arrays:
 *   {
 *     "sourceChainId": 8453,
 *     "sourceContract": "0xB05D424943350aDfadeC4731CD54f12cC45E8c5c",
 *     "fromBlock": 15708166,
 *     "toBlock": 49143677,
 *     "count": 2,
 *     "recipients": ["0xaaa...", "0xbbb..."],
 *     "soulIds":    [0, 1]
 *   }
 * Only `recipients` and `soulIds` are read; the rest is provenance metadata for humans.
 *
 * Required environment variables:
 *   SBT_ADDRESS   deployed WTFSBT1155 on BNB Chain
 * Optional:
 *   HOLDERS_FILE  path to the holder JSON (default "airdrop/base-holders.json")
 *   CHUNK_SIZE    entries per batchMint call (default 100)
 *   SOUL_ID_MAP   JSON object remapping Base soulId -> BSC soulId, e.g. '{"0":"3","1":"4"}'.
 *                 Keys and values are decimal strings. Any soulId absent from the map is
 *                 passed through unchanged. Leave unset when the ids already line up.
 *
 * !! soulIds MUST line up !!
 *   The exported soulIds are Base ids. On BNB Chain, ids are assigned by the order of
 *   createSoul() calls. Either call createSoul() in the exact same order as on Base, or
 *   supply SOUL_ID_MAP. Minting to the wrong id issues the wrong certificate and cannot
 *   be undone except by burning.
 *
 * The broadcasting EOA must be a minter (owner calls addMinter first, removeMinter after).
 *
 * Dry run (simulation only, no transactions):
 *   SBT_ADDRESS=0x... forge script script/Airdrop.s.sol --rpc-url bsc_testnet
 * Broadcast on testnet, then mainnet:
 *   SBT_ADDRESS=0x... forge script script/Airdrop.s.sol --rpc-url bsc_testnet \
 *     --broadcast --private-key $AIRDROP_KEY
 *   SBT_ADDRESS=0x... forge script script/Airdrop.s.sol --rpc-url bsc \
 *     --broadcast --slow --private-key $AIRDROP_KEY
 *
 * See airdrop/README.md for the full runbook.
 */
contract Airdrop is Script {
    WTFSBT1155 internal sbt;
    address[] internal recipients;
    uint256[] internal soulIds;

    function run() external {
        uint256 chunkSize = _chunkSize();
        require(chunkSize > 0, "CHUNK_SIZE must be > 0");

        _load();
        _preflight(chunkSize);
        _broadcast(chunkSize);
    }

    /// @dev Reads SBT_ADDRESS + the holder file into storage, applying SOUL_ID_MAP.
    function _load() internal {
        sbt = WTFSBT1155(payable(_sbtAddress()));

        string memory holdersFile = _holdersFile();
        string memory json = vm.readFile(holdersFile);
        recipients = vm.parseJsonAddressArray(json, ".recipients");
        soulIds = _remapSoulIds(vm.parseJsonUintArray(json, ".soulIds"));

        require(
            recipients.length == soulIds.length,
            "holders file: recipients/soulIds length mismatch"
        );
        require(recipients.length > 0, "holders file: no entries");

        console.log("SBT:            ", address(sbt));
        console.log("holders file:   ", holdersFile);
        console.log("chainid:        ", block.chainid);
        console.log("entries:        ", recipients.length);
    }

    /// @dev Fails before any transaction is sent if the operator setup is wrong.
    function _preflight(uint256 chunkSize) internal view {
        require(
            sbt.isMinter(msg.sender),
            "Airdrop: broadcasting EOA is not a minter. As the contract owner call sbt.addMinter(<airdropEOA>) before running this script, and sbt.removeMinter(<airdropEOA>) after it finishes."
        );
        require(!sbt.paused(), "Airdrop: contract is paused, call unpause()");

        // Every soulId in the file must exist on this chain; fail loudly up front
        // rather than half way through the airdrop.
        uint256 latest = sbt.latestUnusedTokenId();
        for (uint256 i = 0; i < soulIds.length; ++i) {
            require(
                soulIds[i] < latest,
                string.concat(
                    "Airdrop: soulId ",
                    vm.toString(soulIds[i]),
                    " does not exist on this chain (latestUnusedTokenId=",
                    vm.toString(latest),
                    "). Run createSoul() in the same order as Base, or set SOUL_ID_MAP."
                )
            );
        }

        console.log("sender:         ", msg.sender);
        console.log("chunk size:     ", chunkSize);
        console.log("chunks:         ", _chunkCount(chunkSize));
    }

    function _chunkCount(uint256 chunkSize) internal view returns (uint256) {
        return (recipients.length + chunkSize - 1) / chunkSize;
    }

    /// @dev Sends one batchMint per chunk.
    function _broadcast(uint256 chunkSize) internal {
        uint256 total = recipients.length;
        uint256 chunks = _chunkCount(chunkSize);
        uint256 alreadyHeld = 0;

        vm.startBroadcast();
        for (uint256 c = 0; c < chunks; ++c) {
            uint256 start = c * chunkSize;
            uint256 end = start + chunkSize;
            if (end > total) end = total;

            (
                address[] memory toChunk,
                uint256[] memory idChunk,
                uint256 pending
            ) = _slice(start, end);
            alreadyHeld += (end - start) - pending;

            console.log(
                string.concat(
                    "chunk ",
                    vm.toString(c + 1),
                    "/",
                    vm.toString(chunks),
                    ": ",
                    vm.toString(end - start),
                    " entries, ",
                    vm.toString(pending),
                    " to mint"
                )
            );

            if (pending == 0) {
                console.log("  -> all already hold their soul, skipping chunk");
                continue;
            }
            // batchMint itself skips already-holders, so sending the full chunk is safe.
            sbt.batchMint(toChunk, idChunk);
        }
        vm.stopBroadcast();

        console.log("---------------------------------");
        console.log("total entries:  ", total);
        console.log("already held:   ", alreadyHeld);
        console.log("newly minted:   ", total - alreadyHeld);
    }

    /// @dev Copies entries [start, end) out and counts how many still need minting.
    function _slice(
        uint256 start,
        uint256 end
    )
        internal
        view
        returns (address[] memory to, uint256[] memory ids, uint256 pending)
    {
        to = new address[](end - start);
        ids = new uint256[](end - start);
        for (uint256 i = 0; i < to.length; ++i) {
            to[i] = recipients[start + i];
            ids[i] = soulIds[start + i];
            if (sbt.balanceOf(to[i], ids[i]) == 0) {
                ++pending;
            }
        }
    }

    /* ============ Configuration ============
     * Read from the environment. Declared `virtual` so tests can drive the script without
     * mutating process-global env vars (which are shared across test cases).
     */

    function _sbtAddress() internal virtual returns (address) {
        return vm.envAddress("SBT_ADDRESS");
    }

    function _holdersFile() internal virtual returns (string memory) {
        return vm.envOr("HOLDERS_FILE", string("airdrop/base-holders.json"));
    }

    function _chunkSize() internal virtual returns (uint256) {
        return vm.envOr("CHUNK_SIZE", uint256(100));
    }

    function _soulIdMapJson() internal virtual returns (string memory) {
        return vm.envOr("SOUL_ID_MAP", string(""));
    }

    /**
     * @dev Applies the optional SOUL_ID_MAP env var to the exported soulIds.
     * The map is a flat JSON object of decimal-string old->new ids, e.g. {"0":"3","1":"4"}.
     */
    function _remapSoulIds(
        uint256[] memory ids
    ) internal returns (uint256[] memory) {
        string memory mapJson = _soulIdMapJson();
        if (bytes(mapJson).length == 0) {
            return ids;
        }

        string[] memory keys = vm.parseJsonKeys(mapJson, "$");
        uint256[] memory from = new uint256[](keys.length);
        uint256[] memory to = new uint256[](keys.length);
        for (uint256 k = 0; k < keys.length; ++k) {
            from[k] = vm.parseUint(keys[k]);
            // values are decimal strings, e.g. {"0":"3"}
            to[k] = vm.parseUint(
                vm.parseJsonString(mapJson, string.concat(".", keys[k]))
            );
            console.log(
                string.concat(
                    "SOUL_ID_MAP: soulId ",
                    vm.toString(from[k]),
                    " -> ",
                    vm.toString(to[k])
                )
            );
        }

        for (uint256 i = 0; i < ids.length; ++i) {
            for (uint256 k = 0; k < keys.length; ++k) {
                if (ids[i] == from[k]) {
                    ids[i] = to[k];
                    break;
                }
            }
        }
        return ids;
    }
}
