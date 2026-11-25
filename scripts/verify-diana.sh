#!/usr/bin/env bash
# Live checks of QoreChain's PQC precompiles on qorechain-diana, using cast.
# Every step prints before it runs. Each cast call has a 60 s timeout, so a stall is reported.
# Run from the repo root: scripts/verify-diana.sh
RPC="https://evm-testnet.qore.host"
VECTORS="test/vectors/ml-dsa-87.json"
VERIFY=0x0000000000000000000000000000000000000a01
KEYSTATUS=0x0000000000000000000000000000000000000a02
UNREG=0x0000000000000000000000000000000000000001
FAILS=0

say() { echo "[$(date +%H:%M:%S)] $*"; }
call() { timeout 60 cast "$@" --rpc-url "$RPC"; }

say "step 1: chain id"
ID=$(call chain-id) && [ "$ID" = "9800" ] && say "PASS chain id 9800" || { say "FAIL chain id: got '$ID'"; FAILS=$((FAILS+1)); }

say "step 2: pqcKeyStatus for an unregistered account"
KS=$(call call $KEYSTATUS "pqcKeyStatus(address)(bool,uint8,bytes,bool)" $UNREG | tr '\n' ' ' | sed 's/ *$//')
[ "$KS" = "false 0 0x false" ] && say "PASS pqcKeyStatus" || { say "FAIL pqcKeyStatus: got '$KS'"; FAILS=$((FAILS+1)); }

say "step 3: count vectors"
N=$(python3 -c 'import json; print(len(json.load(open("'"$VECTORS"'"))["cases"]))')
say "found $N vectors"

for i in $(seq 0 $((N-1))); do
  say "step 3.$i: vector $i"
  python3 -c 'import json
c = json.load(open("'"$VECTORS"'"))["cases"]['"$i"']
print(c["publicKey"]); print(c["signature"]); print(c["message"])' > /tmp/v.txt
  PK=$(sed -n 1p /tmp/v.txt); SIG=$(sed -n 2p /tmp/v.txt); MSG=$(sed -n 3p /tmp/v.txt)
  R=$(call call $VERIFY "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$MSG")
  [ "$R" = "true" ] && say "PASS vector $i verifies" || { say "FAIL vector $i: got '$R'"; FAILS=$((FAILS+1)); }
  if [ "$i" = "0" ]; then
    say "step 4: tampered message (vector 0)"
    BAD=$(python3 -c 'import sys
b = bytearray.fromhex(sys.argv[1][2:]); b[-1] ^= 1; print("0x" + b.hex())' "$MSG")
    T=$(call call $VERIFY "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$BAD")
    [ "$T" = "false" ] && say "PASS tampered returns false" || { say "FAIL tampered: got '$T'"; FAILS=$((FAILS+1)); }
    say "step 5: gas estimate"
    G=$(call estimate $VERIFY "pqcVerify(bytes,bytes,bytes)(bool)" "$PK" "$SIG" "$MSG")
    say "INFO gas for one pqcVerify on Diana: $G"
  fi
done

say "done: $FAILS failure(s)"
exit $FAILS
