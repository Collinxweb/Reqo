## pqcVerify test vector: status (update 25 November 2026)

**Resolved.** The vector is QoreChain's official ML-DSA-87 vector set.

- Source: https://github.com/qorechain/qorechain-pqc, `vectors/ml-dsa-87.json`, Apache-2.0.
- Copied unmodified to `test/vectors/ml-dsa-87.json` (122,454 bytes), committed in `ce715cd`.
- Five cases. Keys are 2,592 bytes and signatures 4,627 bytes. Messages are `qorechain-pqc/vector/N`.
- On Diana, `pqcVerify` returns `true` for case 0 (checked with `cast`).

**Not covered by any official vector:** `qorechain-msg-v1|qorechain-diana|hello qorechain`. The Reqo prefix needs an end-to-end test once QoreX signing is confirmed.

**Not used:** the QoreSign repo's `vectors/qoresign-v1.json` has message-signing cases in Base64 hybrid form. It is a useful reference for the QoreX signing format, but it isn't the primitive vector we need for `pqcVerify`.
