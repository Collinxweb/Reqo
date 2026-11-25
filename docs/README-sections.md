<!-- Replace the "Post-quantum status" and "Testing" sections of README.md with the text below. -->

## Post-quantum status

Reqo's launch gate is a `pqcVerify` check. `MemeFactoryV4` launches a token only when the creator's registered ML-DSA-87 key signs the exact request:

- **Signature:** `pqcVerify` at `0x…0A01` checks the ML-DSA-87 signature over `qorechain-msg-v1|qorechain-diana|` followed by the request data. The contract builds the message itself. The precompile adds no prefix.
- **Key:** `pqcKeyStatus` at `0x…0A02` must return `registered`, `algorithmId == 1` and `possessionProven`. The submitted public key must equal the registered one.
- **Fail closed:** a failed call, or a result that isn't a 32-byte bool, reverts.
- **Chain behaviour, verified on Diana:** a valid official vector returns `true`. A tampered message returns `false` without reverting. An unregistered account returns `(false, 0, 0x, false)`.
- **Gas, measured on Diana:** one `pqcVerify` call estimates at 311,540 gas, including transaction base cost and calldata.

Limits:
- The app's launch and trade flows depend on QoreX signing, which is not yet confirmed end to end. The requested message has no official vector.
- The contracts are not audited.

## Testing

**Foundry (contracts, local):**
```bash
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge test --match-contract "ReqoV3SecurityTest|ReqoV4Test" -vv
```
These run against the local EVM with mock precompiles. They don't exercise QoreChain's precompiles.

**Diana precompiles (live, `cast`):** see `scripts/verify-diana.sh` (to be added). Each check is a `cast call` against `https://evm-testnet.qore.host`.

**Note on `via_ir`:** `foundry.toml` sets `via_ir = true`. The v4 `createToken` needs it to avoid stack-too-deep. The deployed v3 contracts were compiled without it, so bytecode differs from the source compiled here.
