# Chapter close: Reqo testnet build

Date: 23 November 2026

## Delivered and verified

| Area | Status | Evidence |
|---|---|---|
| v3 contracts on Diana | Deployed and used | WQOR, MemeFactoryV3, a test launch, a pool seed of 10 WQOR and 1000 tokens, a quote matching the formula, a signed swap passing 8 of 8 checks |
| Foundry tests | 16 of 16 pass | `forge test -vv` on the current source |
| Relayer | Removed | No relayer endpoints in `api/`; no owner key in the repo history |
| Reqo app | Working pages | Dashboard, Launch, Trade, Wallet, Reqo AI |
| Reqo AI | Working | Chat through `/api/agent` on `openai/gpt-oss-120b` |
| Documentation | Written | README, AI_USAGE.md, this file |
| Repo originality | Confirmed | First commit 17 November 2026 |

## Open items for submission

| Item | Owner | Blocker |
|---|---|---|
| QCAI two-stage audit | Team | Tool and submission format not yet confirmed |
| `pqcVerify` in the dApp | Team | Call and address not yet confirmed by QoreChain |
| Scoped EVM window | Team | Whether a window can be scoped to target contracts is not confirmed |
| QoreX connection and account match | Team | QFAN reply pending (same seed gives the same account in QoreX and other wallets) |
| Featured image | Team | Not started |
| Video, 3 minutes or less | Team | Not started |
| Project form: GitHub, X, QoreX testnet address connected | Team | To confirm before 2 December |
| Cron job disabled at its service | Team | Not confirmed |
| Owner funds moved to a test account | Team | Not done |

## Not in scope for this chapter

Liquidity, Analytics, native QOR history, Quantum Pass, Encrypted Apps, and any flow that asks users to import a seed phrase.

## Next chapter

1. Confirm QoreX as the connected wallet, and the account match, when QoreChain replies.
2. Run the QCAI audit, and fix findings.
3. Add `pqcVerify` and any scoped window the rubric needs.
4. Build the featured image and the video.
5. Submit before 2 December, 23:59 UTC.
