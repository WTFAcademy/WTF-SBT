#!/usr/bin/env bash
#
# export-base-holders.sh — export the current WTF SBT holder set from Base (chain 8453)
# into the airdrop input file consumed by script/Airdrop.s.sol on BNB Chain (chain 56).
#
# It replays every TransferSingle / TransferBatch log of the legacy Base contract,
# applies mints / burns / transfers, and writes the (address, soulId) pairs that still
# have a non-zero balance.
#
# ---------------------------------------------------------------------------
# Requirements: foundry `cast` and `jq` on PATH.
#
# Environment variables (all optional — defaults target the live Base contract):
#   BASE_RPC_URL       Base JSON-RPC endpoint.       default https://mainnet.base.org
#   BASE_SBT_ADDRESS   legacy WTFSBT1155 on Base.    default 0xB05D424943350aDfadeC4731CD54f12cC45E8c5c
#                      NOTE: 0x2BBE57dA6DFE615B9cE86B2BD149A953af7385d2 is the *Minter*, not the
#                      SBT. If a minter address is passed here the script resolves its wtfsbt()
#                      getter automatically and scans the SBT instead.
#   BASE_START_BLOCK   first block to scan.          default 15708166 (SBT deploy block)
#   BASE_END_BLOCK     last block to scan.           default the chain head at start of run
#   BLOCK_CHUNK        blocks per eth_getLogs call.  default 10000 (public Base RPC hard limit)
#   PARALLEL           concurrent RPC requests.      default 4
#   OUT_FILE           output JSON path.             default airdrop/base-holders.json
#   CACHE_DIR          per-chunk log cache.          default airdrop/.cache/base-logs
#                      Cached chunks are reused, so an interrupted run resumes cheaply.
#                      Delete it to force a full re-scan.
#
# Usage:
#   ./script/export-base-holders.sh              # scan + write OUT_FILE
#   ./script/export-base-holders.sh --dry-run    # scan + print the per-soulId summary only
#
# Notes:
#   * The public Base RPC caps eth_getLogs at a 10,000 block range; the script chunks
#     accordingly and automatically halves a chunk that still gets rejected.
#   * The full history is ~3,400 chunks. Expect tens of minutes on a public endpoint;
#     a private/paid RPC with a larger range limit (raise BLOCK_CHUNK) is much faster.
#   * soulIds in the output are the *Base* soulIds. They must match the soulIds on BNB
#     Chain, or be remapped via the airdrop script's SOUL_ID_MAP. See airdrop/README.md.
#
set -euo pipefail

BASE_RPC_URL="${BASE_RPC_URL:-https://mainnet.base.org}"
BASE_SBT_ADDRESS="${BASE_SBT_ADDRESS:-0xB05D424943350aDfadeC4731CD54f12cC45E8c5c}"
BASE_START_BLOCK="${BASE_START_BLOCK:-15708166}"
BLOCK_CHUNK="${BLOCK_CHUNK:-10000}"
PARALLEL="${PARALLEL:-4}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${OUT_FILE:-$REPO_ROOT/airdrop/base-holders.json}"
CACHE_DIR="${CACHE_DIR:-$REPO_ROOT/airdrop/.cache/base-logs}"

SOURCE_CHAIN_ID=8453
TOPIC_TRANSFER_SINGLE=0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62
TOPIC_TRANSFER_BATCH=0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|--summary) DRY_RUN=1 ;;
    --out) shift; OUT_FILE="$1" ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

for bin in cast jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found on PATH" >&2; exit 1; }
done

log() { printf '%s\n' "$*" >&2; }

# If the caller passed the Minter address by mistake, follow its wtfsbt() getter.
if resolved=$(cast call "$BASE_SBT_ADDRESS" "wtfsbt()(address)" --rpc-url "$BASE_RPC_URL" 2>/dev/null) \
   && [ -n "$resolved" ] && [ "$resolved" != "0x0000000000000000000000000000000000000000" ]; then
  log "note: $BASE_SBT_ADDRESS is a Minter; scanning its SBT $resolved instead"
  BASE_SBT_ADDRESS="$resolved"
fi

END_BLOCK="${BASE_END_BLOCK:-$(cast block-number --rpc-url "$BASE_RPC_URL")}"
log "contract   : $BASE_SBT_ADDRESS (chain $SOURCE_CHAIN_ID)"
log "rpc        : $BASE_RPC_URL"
log "block range: $BASE_START_BLOCK .. $END_BLOCK  (chunk $BLOCK_CHUNK, parallel $PARALLEL)"
log "cache      : $CACHE_DIR"

mkdir -p "$CACHE_DIR"

# ---------------------------------------------------------------------------
# 1. fetch logs chunk by chunk into the cache (one JSON array per chunk file)
# ---------------------------------------------------------------------------
fetch_chunk() {
  # $1 = from block, $2 = to block
  local from="$1" to="$2" file out attempt span mid
  file="$CACHE_DIR/$(printf '%012d-%012d.json' "$from" "$to")"
  [ -s "$file" ] && return 0

  for attempt in 1 2 3 4 5; do
    if out=$(cast logs --rpc-url "$BASE_RPC_URL" --address "$BASE_SBT_ADDRESS" \
               --from-block "$from" --to-block "$to" --json 2>&1); then
      printf '%s' "$out" >"$file"
      return 0
    fi
    # range too large / too many results: split the chunk in half and recurse
    if printf '%s' "$out" | grep -qiE 'range|too many|limited|exceed'; then
      span=$((to - from))
      if [ "$span" -ge 2 ]; then
        mid=$((from + span / 2))
        fetch_chunk "$from" "$mid" && fetch_chunk "$((mid + 1))" "$to" && return 0
      fi
    fi
    sleep $((attempt * 2))
  done
  log "error: failed to fetch logs for blocks $from..$to"
  log "$out"
  return 1
}
export -f fetch_chunk log
export BASE_RPC_URL BASE_SBT_ADDRESS CACHE_DIR

ranges_file="$(mktemp)"
trap 'rm -f "$ranges_file"' EXIT
b="$BASE_START_BLOCK"
while [ "$b" -le "$END_BLOCK" ]; do
  e=$((b + BLOCK_CHUNK - 1))
  [ "$e" -gt "$END_BLOCK" ] && e="$END_BLOCK"
  printf '%s %s\n' "$b" "$e" >>"$ranges_file"
  b=$((e + 1))
done
total_chunks=$(wc -l <"$ranges_file" | tr -d ' ')
cached_chunks=$(ls -1 "$CACHE_DIR" 2>/dev/null | wc -l | tr -d ' ')
log "chunks     : $total_chunks ($cached_chunks cache files already present)"

# shellcheck disable=SC2016
xargs -P "$PARALLEL" -n 2 bash -c 'fetch_chunk "$0" "$1"' <"$ranges_file"
log "fetch      : done"

# ---------------------------------------------------------------------------
# 2. flatten the cached logs into an ordered event stream
#    TSV: kind<TAB>from<TAB>to<TAB>payload
# ---------------------------------------------------------------------------
events_file="$(mktemp)"
trap 'rm -f "$ranges_file" "$events_file"' EXIT

# Cached chunk files may cover a wider range than this run asked for, so filter on the
# decoded block number rather than trusting the glob.
sort_stream() {
  jq -r --arg single "$TOPIC_TRANSFER_SINGLE" --arg batch "$TOPIC_TRANSFER_BATCH" \
        --argjson from "$BASE_START_BLOCK" --argjson to "$END_BLOCK" '
    def h2d: ltrimstr("0x") | explode
      | reduce .[] as $c (0; . * 16 + (
          if   $c >= 48 and $c <= 57  then $c - 48   # 0-9
          elif $c >= 97 and $c <= 102 then $c - 87   # a-f
          else $c - 55                               # A-F
          end));
    .[]
    | select(.removed != true)
    | select(.topics[0] == $single or .topics[0] == $batch)
    | (.blockNumber | h2d) as $bn
    | select($bn >= $from and $bn <= $to)
    | [ $bn, (.logIndex | h2d),
        (if .topics[0] == $single then "S" else "B" end),
        ("0x" + (.topics[2][26:])), ("0x" + (.topics[3][26:])),
        .data ]
    | @tsv
  ' "$CACHE_DIR"/*.json |
    LC_ALL=C sort -t$'\t' -k1,1n -k2,2n |
    cut -f3-
}
sort_stream >"$events_file"
n_events=$(wc -l <"$events_file" | tr -d ' ')
log "events     : $n_events transfer logs"

# ---------------------------------------------------------------------------
# 3. expand TransferBatch rows into single (id, value) rows
# ---------------------------------------------------------------------------
flat_file="$(mktemp)"
trap 'rm -f "$ranges_file" "$events_file" "$flat_file"' EXIT

while IFS=$'\t' read -r kind from to data; do
  if [ "$kind" = "S" ]; then
    # data = 32-byte id || 32-byte value
    printf '%s\t%s\t%s\t%s\n' "$from" "$to" "${data:2:64}" "${data:66:64}"
  else
    # TransferBatch: dynamic uint256[] ids, uint256[] values
    decoded=$(cast decode-abi "f()(uint256[],uint256[])" "$data" 2>/dev/null) || {
      log "warn: could not decode a TransferBatch log, skipping"; continue; }
    ids=$(printf '%s' "$decoded" | sed -n '1p' | tr -d '[] ')
    vals=$(printf '%s' "$decoded" | sed -n '2p' | tr -d '[] ')
    IFS=',' read -r -a id_arr <<<"$ids"
    IFS=',' read -r -a val_arr <<<"$vals"
    for i in "${!id_arr[@]}"; do
      [ -z "${id_arr[$i]}" ] && continue
      printf '%s\t%s\tD%s\tD%s\n' "$from" "$to" "${id_arr[$i]}" "${val_arr[$i]}"
    done
  fi
done <"$events_file" >"$flat_file"

# ---------------------------------------------------------------------------
# 4. replay balances and emit the holder set
# ---------------------------------------------------------------------------
holders_file="$(mktemp)"
trap 'rm -f "$ranges_file" "$events_file" "$flat_file" "$holders_file"' EXIT

awk -F'\t' '
function hex2dec(h,  i, c, n, d) {
  # values prefixed with "D" are already decimal (came out of cast decode-abi)
  if (substr(h, 1, 1) == "D") return substr(h, 2) + 0
  n = 0
  h = tolower(h)
  for (i = 1; i <= length(h); i++) {
    c = substr(h, i, 1)
    d = index("0123456789abcdef", c) - 1
    if (d < 0) continue
    n = n * 16 + d
  }
  return n
}
{
  from = tolower($1); to = tolower($2)
  id = hex2dec($3); val = hex2dec($4)
  if (val == 0) next
  zero = "0x0000000000000000000000000000000000000000"
  if (from != zero) bal[id "\t" from] -= val
  if (to   != zero) bal[id "\t" to]   += val
}
END {
  for (k in bal) if (bal[k] > 0) print k
}
' "$flat_file" | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 >"$holders_file"

n_holders=$(wc -l <"$holders_file" | tr -d ' ')
log ""
log "=== holder summary (block $BASE_START_BLOCK..$END_BLOCK) ==="
awk -F'\t' '{c[$1]++} END {for (i in c) printf "  soulId %-4s %6d holders\n", i, c[i]}' \
  "$holders_file" | LC_ALL=C sort -k2,2n
log "  ------------------------------------"
log "  total entries to mint: $n_holders"
log ""

if [ "$DRY_RUN" = "1" ]; then
  log "--dry-run: $OUT_FILE not written"
  exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
jq -n \
  --argjson sourceChainId "$SOURCE_CHAIN_ID" \
  --arg sourceContract "$BASE_SBT_ADDRESS" \
  --argjson fromBlock "$BASE_START_BLOCK" \
  --argjson toBlock "$END_BLOCK" \
  --argjson count "$n_holders" \
  --rawfile rows "$holders_file" '
  ($rows | rtrimstr("\n") | if . == "" then [] else split("\n") end
         | map(split("\t"))) as $r
  | {
      sourceChainId: $sourceChainId,
      sourceContract: $sourceContract,
      fromBlock: $fromBlock,
      toBlock: $toBlock,
      count: $count,
      recipients: ($r | map(.[1])),
      soulIds:    ($r | map(.[0] | tonumber))
    }
' >"$OUT_FILE"

log "wrote $OUT_FILE ($n_holders entries)"
