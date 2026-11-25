## Security review status (update 25 November 2026)

| ID | Severity | Title | Status |
|---|---|---|---|
| F1 | Medium | On-chain symbol and name validation | **Fixed in v4**: printable ASCII names, A-Z/0-9 tickers. Mock tests written; run pending. |
| F2 | Low | Third party submits a creator's signed request | **Fixed in v4**: relayed path removed; only the creator can launch. |
| F3 | Informational | Front-running a permit breaks a swap | **Closed, claim withdrawn**: a front-run permit leaves the allowance set, so the pool skips its own permit and the swap succeeds. Covered by `test_F3_permitFrontRunDoesNotBreakSwap` (run passed on v3). |
| F4 | Low | Tokens sent directly to a pool are unrecoverable | Open, by design: no owner, no rescue. Documented. Test passed on v3. |
| F5 | Low | Image URL accepts any HTTPS host (front end) | Open. Fix: accept only the Vercel Blob host. |
| F6 | Informational | No admin, pause or upgrade path | By design. |
| F7 | Informational | Sandwich risk bounded by slippage | By design. Default slippage should be 1%. |
| F8 | Informational | One RPC call per token on the dashboard | Open. Fix: an event index or pagination. |

### New on-chain verification (v4 precompile dependencies)
- `pqcVerify` (0x…0A01): valid vector returns `true`; tampered message returns `false`, no revert. Verified on Diana with `cast`.
- `pqcKeyStatus` (0x…0A02): unregistered account returns the documented tuple. Verified on Diana with `cast`.
- Foundry fork tests cannot exercise these precompiles, so they are not evidence for this table.

### Open
- Run the v4 mock tests (14).
- Full `createToken` gas after deployment.
- F5 and F8 fixes in the front end.
