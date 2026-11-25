# Reqo: Project Progress Log

Living document. Every release, decision, and verified fact gets added here. Newest entries go at the top of the Changelog.

Status key: **[verified]** confirmed on chain or by a working test. **[unverified]** assumed or read from docs, not tested. **[open]** unresolved.

---

## 1. Summary

Reqo is a memecoin launchpad on QoreChain testnet (Diana). Users create tokens from a web page, and the factory records each token and its creator. The current build only works for the account that holds an open EVM window, so the v2 plan moves signing and creation to a relayer. See section 7.

## 2. Links

| Item | Value |
|---|---|
| Live page | https://reqo-seven.vercel.app |
| GitHub repo | https://github.com/Collinxweb/Reqo |
| Vercel project | reqo (collinxweb1) |
| Local repo (Termux) | ~/Reqo |

## 3. Network (QoreChain Diana testnet)

| Item | Value | Status |
|---|---|---|
| Cosmos chain ID | qorechain-diana | [verified] from node_info |
| EVM chain ID | 9800 (0x2648) | [verified] from eth_chainId |
| Native token | QOR (base denom uqor, 6 decimals) | [verified] balances in uqor |
| EVM RPC | https://evm-testnet.qore.host | [verified] |
| REST API | https://api-testnet.qore.host | [verified] |
| CosmWasm | Live, codes deployed, all with instantiate permission "Nobody" | [verified] |
| Faucet | Accepts qor1... addresses only | [verified] |

Default endpoints in the SDK point to localhost. Use the public URLs above.

## 4. Accounts (public addresses only)

| Role | EVM address | Native address | Notes |
|---|---|---|---|
| Owner / deployer / test creator | 0xC37C97Fd878DF9Ce4C5a6a2dA9D33C8Ed6700a1B | qor1cd7f0lv83huuunz6dgk6n5eu3mt8qzsmm35g8j | Same account, verified by matching balances. Holds about 188.8 QOR and test fETH, fUSD, fBTC. |
| Earlier faucet account | 0xe11c28f65177481a7cfe165e214c32482b10191d | qor1uywz3aj3wayp5l87ze0zznpjfq43qxgam8ysyt | Received 10 QOR from faucet. Not the deploy account. |

**Secrets rule:** Private keys, seed phrases, and API tokens never go in chat, in the repo, or in any file. Keys are entered only at the hidden `read -s` prompt in Termux, and history is cleared after each run.

## 5. Contracts

### v1 MemeFactory (Solidity, EVM)

| Item | Value | Status |
|---|---|---|
| Factory address | 0x6944168F50aCCBB602c519a0f85B17610E06594b | [verified] has code |
| Deploy tx | 0x276e020837f449e0036110fbed515602b422da48fb81195a6671fa1bc2fc5323 | [verified] |
| Test token (v1) | 0x4a27Dc2dBCdBb0Ec44a472403b46F9558290d9c1 | [verified] |
| Test token create tx | 0xb0b9d3fb0e7641c6ec60dd1e65f91b59589a79a5291d5eb53afc3a0889082d80 | [verified] status 1 |
| Test token name / symbol / supply | Test Cat / TCAT / 1000 raw | [verified] |
| Test token creator | 0xC37C...1B | [verified] balanceOf creator = 1000 |

**Functions:** `createToken(name, symbol, supply, description)`, `tokenCount()`, `tokens(i)`, `creatorOf(token)`, event `TokenCreated`.

**Checks in code:** name 1 to 32 chars ("bad name"), symbol 1 to 10 chars ("bad symbol"), supply greater than 0 ("zero supply").

**Known limits:**
- Trusts `msg.sender` as creator. Cannot be used for relayed creation. Fixed in v2.
- Supply stored as raw units, no decimals applied. A token with supply 1000 has a `decimals()` of 18, so wallets show 0.000000000000001000. Fix in v2 by scaling in the factory or documenting whole-token input.
- No `createToken` restrictions. Anyone with gas can create tokens.

## 6. EVM Authorization Window (verified behaviour)

- A window is per account. It only permits transactions from that account.
- Open it from the Dashboard or QoreX, on an Ethereum (coin type 60) account. A standard qor1 (coin 118) account can't sign for its EVM address.
- Requires a registered ML-DSA-87 key. Registration and open/close use the PQ key. Transactions inside the window are signed by the normal EVM key.
- Query: `GET https://api-testnet.qore.host/qorechain/pqc/v1/evm_window/<qor1 address>`. Use the qor1 address, not 0x. Check `live`, `remaining_blocks`, and `remaining_txs`.
- Limits seen: `blocks` up to 17,280 (about 6 hours on testnet), `max_txs` up to 1,000, `max_value` in uqor (counts value plus max fee). `native_only` false means contract creation is allowed.
- Don't set `allowed-targets` on a window used for deploys, because contract creation is refused under a scope.
- Windows expire on their own. There is no permanent window.
- **Observed:** window expiry during use caused the frontend error "could not coalesce error".

## 7. Decisions

| # | Decision | Reason | Status |
|---|---|---|---|
| D1 | Use the Solidity/EVM route for now | v1 is tested on Remix VM and deployed on diana. | Accepted |
| D2 | Build v2 with relayer and EIP-712 signed creation (Option 1) | Lets any EVM wallet create tokens without its own window. Creator is the signer. | Accepted, not built |
| D3 | Keep native CosmWasm (Option 2) as research only | Needs a Rust rewrite and native signing is unverified. | Research |
| D4 | No always-open window | Windows are time-limited by design. | Accepted |
| D5 | Each release is one file with a unique name, plus a version on the page | Avoids collisions like the Epoch index.html incident. | Accepted |

## 8. Open Questions

| # | Question | How to resolve |
|---|---|---|
| Q1 | Does the chain accept a relayed `createToken` when the user has no window? | Test with a second account, or with the relayer on Remix VM first, then diana. |
| Q2 | Can the relayer window be renewed automatically, and how often? | Read the Dashboard/QoreX docs, or ask in Discord. |
| Q3 | How does the native QoreChain wallet sign, and does it need a window? | Test with a second account. |
| Q4 | Can the Dashboard open windows for accounts other than your own? | Test with a second account. |
| Q5 | Is there a sponsored or reusable window option for apps? | Ask QoreChain on Discord. |
| Q6 | Does Brave's wallet connect to the Diana account with the window? | Test on the live page after a window is open. |

## 9. Changelog

Newest first.

| Version | Date | Commit | Change |
|---|---|---|---|
| v1.1.1 | 2026-11-17 | (pending) | Restores the Reqo page. v1.1 had accidentally committed another project's index.html. Adds version label. Uses unique filename reqo-v1.1.1.html. |
| v1.1 | 2026-11-17 | cc0dc34 | Wallet prompt to switch to chain 9800, or add it if unknown. Committed the wrong index.html, so the live page showed another project. Fixed in v1.1.1. |
| v1.0 | 2026-11-17 | aec59c7 | First frontend. Lists tokens from the factory. Create button for wallet browsers. |
| v1 contracts | 2026-11-17 | n/a | MemeFactory deployed to diana, test token created. Verified with eth_getCode, tokenCount, name, supply, and balance. |
| v1 contracts (Remix VM) | 2026-11-17 | n/a | Factory tested locally: create, tokenCount, tokens, creatorOf, balanceOf. |

## 10. Known Issues

| # | Issue | Impact | Fix |
|---|---|---|---|
| I1 | Create works only for the window's account | Other users can't create tokens | v2 relayer (D2) |
| I2 | Expired window gives "could not coalesce error" | Confusing failure | v1.2.0 window-status check, plus raw error text |
| I3 | Supply has no decimals | Wallets show tiny balances | v2 scaling or documented input |
| I4 | Same-name files across projects in Downloads | Wrong file committed | Unique filenames per release (done) |
| I5 | Brave wallet account not confirmed to match the window account | Transactions may fail | Check wallet address before testing (Q6) |

## 11. Release Format

Every update follows this block. Add it to the changelog and the release notes in the same commit.

- **Version:** vX.Y.Z (patch for fixes, minor for features, major for contract changes)
- **File:** `reqo-vX.Y.Z.html` for the page, or `reqo-vX.Y.Z-contracts.md` for contract notes
- **Change:** one line
- **Commit:** `vX.Y.Z: short description`
- **Checks before push:** version string present in the file, `git diff --stat` size matches the change, no other project's content
- **Checks after deploy:** `curl -s https://reqo-seven.vercel.app | grep -o "Reqo vX.Y.Z"`
- **Docs:** update this file, sections 5, 6, 8, 9, 10 as relevant, in the same commit

## 12. Next Steps

1. Write v2 factory with `createTokenFor` and EIP-712 signature checks. Test on Remix VM: valid signature, reused nonce, expired deadline, wrong signer.
2. Fix decimals in v2 (I3).
3. Redeploy to diana with the relayer account. Keep v1 as a record.
4. Build a relayer endpoint on Vercel: holds the key in an environment variable, rate-limits by wallet, verifies the signature before submitting.
5. Update the page for v2: connect, sign, submit to relayer.
6. Resolve Q1 through Q6 by testing with a second account.
