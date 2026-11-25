## v4 launch gate and Diana verification (25 November 2026)

### Built
- `MemeFactoryV4` (`src/ReqoV4.sol`): a token launches only when the caller's ML-DSA-87 key signs the exact request. The gate calls `pqcVerify` at `0x…0A01`. The key comes from `pqcKeyStatus` at `0x…0A02`, which must return `registered`, `algorithmId == 1` and `possessionProven`. The submitted public key must equal the registered one.
- Signed message: `"qorechain-msg-v1|qorechain-diana|" || abi.encode(DOMAIN_TAG, chainid, factory, creator, nonce, deadline, name, symbol, supply, keccak256(description))`. The contract builds it, so the caller can't choose a different message.
- Fail closed: a failed staticcall, or a result that isn't a 32-byte bool, reverts. No default passes.
- F1 fix: names are printable ASCII, tickers are A-Z or 0-9.
- F2 fix: the relayed path is removed, so only the creator can launch.
- Pool and token unchanged from v3.

### Tests
- `test/ReqoV4.t.sol`: 14 mock-based tests, covering the gate, possession, key ownership, expiry, nonce replay, the message, and the ASCII rules. **Status: written against the documented interface, not yet run.** The previous 13-test version passed against the earlier placeholder interface, so it doesn't count.
- Foundry fork tests for the precompiles fail locally. A local fork doesn't include the node's built-in precompiles, so calls to `0x…0A01` and `0x…0A02` return nothing. Precompile behaviour is verified with `cast` against the live node.

### Verified on Diana (`qorechain-diana`, chain 9800), with `cast`
| Check | Result | Expected | Status |
|---|---|---|---|
| `pqcKeyStatus(0x…0001)` (unregistered) | `false`, `0`, `0x`, `false` | Documented result | Verified |
| `pqcVerify` on official vector 0 | `true` | Valid signature | Verified |
| `pqcVerify` with last message byte changed to `ff` | `false`, no revert | Documented behaviour | Verified |
| `cast estimate` for one `pqcVerify` call | 311,540 gas | Documented precompile charge is about 85k; the estimate includes transaction base and calldata | Verified, Diana |

Still to measure: the full `createToken` gas, once v4 is deployed.

### Vector
- Source: `qorechain/qorechain-pqc`, `vectors/ml-dsa-87.json`, Apache-2.0, copied unmodified to `test/vectors/ml-dsa-87.json` (122,454 bytes).
- Five cases, public keys 2,592 bytes and signatures 4,627 bytes. Messages are `qorechain-pqc/vector/N`.
- The requested message `qorechain-msg-v1|qorechain-diana|hello qorechain` is not in any official vector. The Reqo prefix still needs an end-to-end test once QoreX signing is confirmed.

### Corrections to earlier claims
- **Front-running a permit does not break a swap.** The pool skips its own permit when the allowance is already set. The README must not say otherwise.
- **The chain accepts deterministic and hedged ML-DSA-87 signatures.** The earlier "deterministic only" claim was wrong.
- **QoreX `signArbitrary` availability is unconfirmed** in the live extension. The `QOREX_NOT_SUPPORTED_YET` message came from a mock wallet profile, per QoreChain.

### Open
1. Confirm `lib/` is untracked: `git ls-files | grep -c "^lib/"` should print `0`.
2. Run the 14 v4 mock tests and record the result.
3. Measure the full `createToken` gas after deployment.
4. Confirm QoreX `signArbitrary` against the live extension, including the Base64 PQ signature decoding.
5. Ticker uniqueness: a product decision, still open.
6. Decide whether the fork-test file keeps only the file-size check.
