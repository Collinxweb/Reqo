#!/usr/bin/env bash
# Verifies QoreChain's PQC precompiles on qorechain-diana against the live node, using cast.
# A local Foundry fork cannot run the chain's built-in precompiles, so these checks run on the node.
#
# Requires: cast (Foundry), python3, network access to the RPC.
# Usage (from the repo root): scripts/verify-diana.sh
set -euo pipefail

RPC="${RPC:-https://evm-testnet.qore.host}"
VECTORS="${VECTORS:-test/vectors/ml-dsa-87.json}"
PQC_VERIFY=0x0000000000000000000000000000000000000a01
PQC_KEY_STATUS=0x0000000000000000000000000000000000000a02
UNREGISTERED=0x0000000000000000000000000000000000000001

fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 (got: $2)"; fails=$((fails + 1)); }

command -v cast >/dev/null || { echo "cast not found: install Foundry first"; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found"; exit 2; }
[ -f "$VECTORS" ] || { echo "vector file not found: $VECTORS"; exit 2; }

# 1. Chain identity
chain=$(cast chain-id --rpc-url "$RPC")
if [ "$chain" = "9800" ]; then pass "chain id is 9800 (qorechain-diana)"; else fail "chain id is 9800" "$chain"; fi

# 2. pqcKeyStatus for an unregistered account: documented result (false, 0, 0x, false)
ks=$(cast call "$PQC_KEY_STATUS" "pqcKeyStatus(address)(bool,uint8,bytes,bool)" "$UNREGISTERED" --rpc-url "$RPC" | tr '\n' ' ' | sed 's/ *$//')
if [ "$ks" = "false 0 0x false" ]; then pass "pqcKeyStatus: unregistered account"; else fail "pqcKeyStatus: unregistered account" "$ks"; fi

# 3. pqcVerify on every official vector must return true
count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["cases"]))' "$VECTORS")
for i in $(seq 0 $((count - 1))); do
  read -r PK SIG MSG < <(python3 -c 'import json,sys
c = json.load(open(sys.argv[1]))["cases"][int(sys.argv[2])]
print(c["publicKey"], c["signature"], c["message"])' "$VECTORS" "$i")
  r=$(cast call "$PQC_VERIFY" "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$MSG" --rpc-url "$RPC")
  if [ "$r" = "true" ]; then pass "pqcVerify: official vector $i verifies"; else fail "pqcVerify: official vector $i verifies" "$r"; fi

  # 4. Tampered message (last byte flipped) must return false, not revert
  if [ "$i" = "0" ]; then
    BAD=$(python3 -c 'import sys
b = bytearray.fromhex(sys.argv[1][2:])
b[-1] ^= 1
print("0x" + b.hex())' "$MSG")
    t=$(cast call "$PQC_VERIFY" "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$BAD" --rpc-url "$RPC" 2>&1 || true)
    if [ "$t" = "false" ]; then pass "pqcVerify: tampered message returns false (no revert)"; else fail "pqcVerify: tampered message returns false" "$t"; fi

    # 5. Gas for one verification on Diana (node estimate, includes tx base and calldata)
    gas=$(cast estimate "$PQC_VERIFY" "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$MSG" --rpc-url "$RPC")
    echo "INFO  pqcVerify gas on Diana (vector 0): $gas"
  fi
done

echo
if [ "$fails" -eq 0 ]; then echo "All Diana checks passed."; else echo "$fails check(s) failed."; fi
exit "$fails"
