# Security review: Reqo v3 contracts

Scope: `MemeFactoryV3`, `PoolV3`, `MemeTokenV3`, `WQOR` (`src/ReqoV3.sol`), as deployed on QoreChain Diana testnet (factory `0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f`, WQOR `0xF78c2cC7dc1B9ae52403868dD2097732Abfca665`).
Out of scope: front-end code, the Reqo AI endpoint, the window and account proxies, and QoreChain's precompiles.
Method: line-by-line reading against the Solidity and OpenZeppelin v5 behaviour; each finding was checked against the code path before it was recorded.
Status: review only. No code has been changed. Findings marked "test" have a Foundry test in `test/ReqoV3.security.t.sol`, which has not yet been run.

## Summary

| ID | Severity | Title | Status |
|---|---|---|---|
| F1 | Medium | Symbol and name are length-checked only; any bytes and duplicates are accepted | Open, test |
| F2 | Low | Relayed creation can be submitted by a third party with the creator's signature | Open, test |
| F3 | Informational (corrects an earlier claim) | Front-running a permit does not make a swap fail | Closed by analysis, test |
| F4 | Low | Tokens sent to a pool directly cannot be recovered | Open, test |
| F5 | Low | Image URL in the description accepts any HTTPS host (front end) | Open |
| F6 | Informational | No admin, pause or upgrade path | By design |
| F7 | Informational | Sandwich risk on swaps is bounded only by the trader's minimum output | By design |
| F8 | Informational | Dashboard and Trade fetch every token with one RPC call per token | Open |

No finding gives a third party access to funds, lets a pool be drained, or lets a supply be minted after launch. The core invariants hold in the code paths reviewed.

## Checked and fine

- **No mint after launch.** `MemeTokenV3` mints only in its constructor, to the factory. The factory moves the whole supply into the pool.
- **No liquidity withdrawal.** `PoolV3` has no function that sends tokens or WQOR out except `swap`, which pays the trader and enforces `out < reserve`.
- **Reserves are accounting, not balances.** `swap` prices from `tokenReserve` and `wqorReserve`. A transfer to the pool does not change prices. This is what makes F4 harmless to pricing.
- **Constant product holds.** After every swap, `wqorReserve * tokenReserve >= kBefore`, checked explicitly. The fee stays in the pool, so `k` grows.
- **Rounding favours the pool.** `quoteOut` floors the output, and a zero output reverts with `slippage`.
- **Signature binding.** Intent hashes use EIP-712 with the pool address as `verifyingContract`, so a signature cannot be replayed on another pool or chain. OpenZeppelin's `ECDSA.recover` rejects malleable signatures and reverts on invalid ones, so the comparison with `trader` cannot be satisfied by `address(0)`.
- **Nonces are consumed only on success.** `nonceUsed` is set before the transfers, but a later revert rolls the whole transaction back, so a failed swap does not burn a nonce.
- **Seeding is single-use and factory-only.** `seed` requires `msg.sender == factory` and `!seeded`, and the pool is created in the same transaction as its seed.
- **Reentrancy.** `swap`, `createToken` and `createTokenFor` are `nonReentrant`. `WQOR.withdraw` burns before it sends native QOR and is `nonReentrant`. The token and WQOR contracts have no transfer hooks.
- **Relayed creation replay.** `createTokenFor` records `nonceUsed[creator][nonce]` and the digest includes the factory's domain, so a request cannot be replayed on another factory.

## F1: Symbol and name are not validated on-chain (Medium)

**Where:** `MemeFactoryV3._create`, lines 278-279.

`_create` checks only that the symbol is 1 to 10 bytes and the name is 1 to 32 bytes. It does not check the character set. Any caller of `createToken` can pick a symbol such as `USDC` with a Cyrillic letter, or a symbol that is already used. The Reqo app blocks these in the UI, and the Reqo AI check warns about duplicates, but the contract accepts anything.

**Impact:** a token can impersonate another token on wallets and explorers that show the symbol but not the address. Anyone can also create several tokens with the same ticker. Users who rely on the symbol are exposed, and the contract gives no signal that the token is a copy.

**How to check:** call `createToken` with the symbol bytes `d0 a1` (Cyrillic С). It succeeds. Call it twice with the same symbol. Both succeed.

**Fix:** require the symbol to match `[A-Z0-9]{1,10}` and the name to be printable ASCII, in `_create`. Decide whether tickers must be unique. Uniqueness needs a `mapping(bytes32 => address)` keyed by the symbol hash, and it changes the launch rules, so it is a product decision. The contract cannot be changed in place, so this needs a v4 factory, which is already planned for the `pqcVerify` gate.

**Test:** `test_F1_nonAsciiSymbolAccepted`, `test_F1_duplicateSymbolAccepted`. Both assert the current behaviour and are expected to flip once fixed.

## F2: Relayed creation can be submitted by a third party (Low)

**Where:** `MemeFactoryV3.createTokenFor`, lines 239-252.

The signature covers the creator, name, symbol, supply, description, nonce and deadline, but not the caller. Any holder of a signed request can submit it and pay the WQOR seed. The creator gets no tokens in either case, since launches allocate nothing to the creator.

**Impact:** the submitter chooses the moment of launch and pays the seed. A creator who signs a request and expects to pay for it can have it executed by someone else. The creator's nonce is consumed, so the request cannot be reused. No funds of the creator are at risk, because the creator's WQOR is never pulled, but the creator is no longer the payer.

**Fix:** include the payer or the caller in the signed struct, or require `msg.sender == r.creator` for relayed creation. The relayer design was removed from the product, so the second option is the simpler one.

**Test:** `test_F2_thirdPartyRelaysCreatorRequest`. It shows the request executes and the seed comes from the relayer.

## F3: Front-running a permit does not break a swap (Informational, corrects an earlier claim)

**Where:** `PoolV3.swap`, lines 153-155.

Earlier documentation said that front-running a permit signature can make the trader's swap fail. That is not right for this code. If someone submits the trader's permit first, the allowance becomes `amountIn`. The `swap` check `allowance < amountIn` is then false, so the pool skips its own permit call and the swap succeeds.

**Action:** remove the front-running claim from the README and the progress log, or replace it with this analysis. The only effect of a front-run is that someone else pays the gas for the permit.

**Test:** `test_F3_permitFrontRunDoesNotBreakSwap`.

## F4: Tokens sent to a pool directly are unrecoverable (Low)

**Where:** `PoolV3`, no rescue function.

Pricing uses reserves, so a direct transfer does not move the price. But the tokens are then stuck: nothing in the pool can send them out, and this is intentional because the pool has no owner. Anyone who sends tokens to a pool address by mistake loses them.

**Fix:** none needed for safety. Document it in the README and in the UI for the pool address. A rescue function would reintroduce an admin, which conflicts with the "no owner" design.

**Test:** `test_F4_donationDoesNotChangePrice`, which also shows the donated tokens stay in the pool.

## F5: Image URL accepts any HTTPS host (Low, front end)

**Where:** the front end's `imgFrom` helper, which accepts any `https://` URL after `img:` in the description.

The contract does not check the link. The front end then loads it in the user's browser, so a creator can point the image at any server, which reveals the user's IP and can be used for tracking. The image is shown with `referrerPolicy="no-referrer"`, which limits the referrer leak but not the IP.

**Fix:** accept only the Vercel Blob host in the front end, and show other links as text.

## F6: No admin, pause or upgrade path (Informational, by design)

Positive for trust: there is no owner who can change prices, pause trading or take funds. The cost is that a bug found after launch cannot be stopped. The v4 factory should state this trade-off explicitly in the README.

## F7: Swap sandwich risk is bounded only by minimum output (Informational, by design)

Once a signed intent is public, anyone can submit it, and the price can move before it lands. `minOut` bounds the loss at the chosen slippage, so a trader who uses 5% can lose up to 5% on a trade. The front end's default should be 1%, and the README should explain the trade-off.

## F8: Dashboard and Trade load every token with one RPC call per token (Informational)

The front end reads each token's name, symbol, description, supply and pool separately. That scales linearly with the number of launches and will slow the page as the factory grows. This is not a contract issue. The fix is an event index, or pagination in the front end.

## Repo hygiene

- The key check on the repo history found no private key that matches the owner or the test account. The check was run once; see the progress log for its result.
- `lib/` is ignored and untracked. The Foundry tests live in `test/`.
- The README must not describe the relayer or claim that front-running breaks swaps (F3).

## Open items

1. Run `test/ReqoV3.security.t.sol` in the Codespace. Each test's result must be recorded before any finding is marked closed.
2. Decide whether launch tickers must be unique (F1). This is a product decision, and it has to be made before the v4 factory is written.
3. Fix F5 in the front end.
