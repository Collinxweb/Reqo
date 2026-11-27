# Reqo

Reqo is a memecoin launchpad and swap app on QoreChain testnet (Diana, chain ID 9800). Each token launches with its full supply and a fixed WQOR seed in a constant-product pool. Trades are signed by the trader and submitted by a relayer, so traders pay no gas for swaps.

**Status: testnet only. Not audited. Do not use with real funds.**

- App: https://reqo-seven.vercel.app
- Docs page: https://reqo-seven.vercel.app/docs.html
- Source: https://github.com/Collinxweb/Reqo
- Explorer (Testnet): https://dashboard.qorechain.io/explorer/tx/<transaction hash>

## What is live

| Area | Status |
|---|---|
| Launch a token (signed request, relayed) | Live on Diana. Launches are queued when the relayer window is closed. |
| Token image (PNG, JPEG, WebP, up to 1 MB) | Live. Stored in Vercel Blob, linked from the token description as `img:<url>`. |
| Swap (buy and sell on a token's pool) | Contracts verified on Diana (8 of 8 checks). Trade page live. |
| WQOR allowance for traders | Live. 5 WQOR per address, relayer-funded, rate limited. |
| Wallet | Live. Balances (native QOR, WQOR, all Reqo tokens), send, receive, history from the chain. |
| Quantum-safe account card | Live. Shows the qor1 address, registration response, and window status. |
| Onboarding | Live. Points users to QoreX first, then the relayer path. |
| Light and dark themes | Live. |
| Liquidity, Analytics | Coming soon. Liquidity needs a contract change. |
| Native QOR transfer history | Not yet. Native transfers emit no logs. |

## Network

- RPC: `https://evm-testnet.qore.host`
- REST: `https://api-testnet.qore.host`
- Chain ID: 9800 (`0x2648`)
- Native token: QOR. 18 decimals on the EVM side, 6 decimals (`uqor`) on the native side.
- Faucet: `qor1` addresses only.

## Contracts (Diana)

| Contract | Address | Role |
|---|---|---|
| WQOR | `0xF78c2cC7dc1B9ae52403868dD2097732Abfca665` | Wrapped QOR, the quote asset. Deposit and withdraw at 1:1. |
| MemeFactoryV3 | `0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f` | Current factory. Creates tokens and pools. EIP-712 domain version `3`. |
| MemeFactoryV2 | `0xbEe5D528b86fDe7bd68a1330B4A76E838390d356` | Record only. Tokens launched here have no pool and cannot be traded. |
| MemeFactory (v1) | `0x6944168F50aCCBB602c519a0f85B17610E06594b` | Superseded. Not used by the app. |

Each v3 token has its own `MemeTokenV3` (ERC-20 with permit) and `PoolV3` (constant product, signed swaps).

### Example launch (verified)

- Token: `0xa2FAD0D37996529f758fEc6fe295c5e961d6fD00`
- Pool: `0x97247263A1Ed75005d2a927DfC5e7002266c80E7`
- After launch: pool holds 1000 tokens and 10 WQOR, `seeded = true`.

## How it works

### Launch

1. The user fills in name, ticker, supply, description, and an optional image.
2. The user's wallet signs an EIP-712 `CreateRequest` (no transaction, no gas).
3. The relayer checks the signature, the deadline, and the nonce, then submits `createTokenFor` on MemeFactoryV3.
4. If the relayer window is closed, the request is queued in Upstash Redis and processed when the window opens.
5. The factory mints the full supply, creates the pool, and seeds it with 10 WQOR from the relayer account.

Supply limit: up to 1e12 whole tokens. Name up to 32 bytes, symbol up to 10 bytes, description up to 280 bytes.

### Trade (swap)

1. The trader chooses buy (WQOR for token) or sell (token for WQOR) and a slippage limit (1%, 3%, or 5%).
2. The trader signs an ERC-2612 permit for the input token and an EIP-712 `Swap` intent (trader, direction, amount in, minimum out, nonce, deadline).
3. The relayer checks the signatures, that the pool is registered for the token, that the nonce is unused, and that the relayer window is open. It then submits `swap`.
4. The pool enforces the signed minimum output, deadline, nonce, and signer. Replays, expired intents, and intents signed by another key are rejected.

Pool math: `amountOut` follows the constant-product formula with a 0.3% fee. The fee stays in the pool. Liquidity cannot be withdrawn by anyone, including the token creator. Creators receive no tokens at launch.

Verified: a buy of 1 WQOR returns 90.661089388 tokens, which matches the independent calculation.

### WQOR allowance

The relayer sends up to 5 WQOR per address in total. The wallet requests it from the Trade page when the WQOR balance is zero. Requests are refused when the relayer window is closed.

### Relayer window

The relayer account can only submit transactions while a QoreChain EVM authorisation window is open on its account. Windows are opened and closed by the account holder in QoreX. The app cannot open one. Scheduled windows are planned for 01:00 and 13:00 UTC, five hours each; opening is currently manual. The relayer reads the window status from the window endpoint before submitting.

## Pages

- `index.html`: Board (token list, search, sort), Launch, More.
- `trade.html`: Swap card with From and To panels, rate, price impact, minimum received, slippage, balance check, and a History tab.
- `wallet.html`: wallet card, Send, Receive, Your Tokens (with images), History, Trades, Activity, quantum-safe account card, and first-visit onboarding.
- `docs.html`: public documentation page.

## Relayer API

Serverless functions in `api/`:

| Route | Method | Purpose |
|---|---|---|
| `/api/relay` | POST | Accepts a signed launch request. Submits it, or queues it when the window is closed. |
| `/api/status` | GET | Window state. With `?id=`, the state of one queued request. |
| `/api/process` | GET | Processes the queue while the window is open. Requires the cron secret. |
| `/api/swap` | POST | Accepts a signed trader permit and intent. Submits `swap`. |
| `/api/faucet` | POST | Sends the WQOR allowance to an address. |
| `/api/upload` | POST | Stores a token image (PNG, JPEG, WebP, up to 1 MB, checked by magic bytes). |

Rate limits: launches 5 per hour per address, swaps 10 per hour per address, faucet 10 per hour per network, uploads 10 per hour per IP. These limits are held in memory on the serverless instance. They are not yet persisted (see Known limits).

## Configuration

Environment variables, set in the Vercel project. Values are never stored in the repository.

| Name | Used by |
|---|---|
| `OWNER_PK` | Relayer account private key |
| `CRON_SECRET` | Authorises `/api/process` |
| `KV_REST_API_URL`, `KV_REST_API_TOKEN` | Upstash Redis queue |
| `BLOB_READ_WRITE_TOKEN` | Vercel Blob for token images |

The relayer account is `0xC37C97Fd878DF9Ce4C5a6a2dA9D33C8Ed6700a1B` (native `qor1cd7f0lv83huuunz6dgk6n5eu3mt8qzsmm35g8j`).

## Post-quantum accounts

QoreChain signs native transactions with a hybrid signature: classical plus ML-DSA-87 (FIPS 204). The ML-DSA-87 key is registered per account on chain.

- Keys are generated and held in QoreX, the official QoreChain wallet. Reqo does not generate or store ML-DSA-87 keys.
- Direct sends from a MetaMask-held key need the account's ML-DSA-87 key to be registered and an authorisation window to be open. Reqo checks the window before a direct send.
- Trades and launches are relayed. They do not need the user's key.
- Only the account holder can open or close a window, from QoreX. A website cannot request it.
- QoreX is available for Firefox desktop (add-on listing: `addons.mozilla.org/firefox/addon/qorex/`). Mobile and Chrome links are pending confirmation from QoreChain.

Address mapping: the wallet's `0x` address maps to the account's `qor1` address (bech32, prefix `qor`). The mapping was checked against the owner account. It is assumed to hold for every account that uses the same seed phrase in QoreX and MetaMask. That assumption is unconfirmed.

## Verified results

- Launch on v3: pool seeded with 1000 tokens and 10 WQOR, `seeded = true`.
- Quote: 1 WQOR buys 90.661089388 tokens, matching the constant-product formula with fee.
- Signed swap: 8 of 8 checks (fill at or above minimum, reserve change equals amount out, trader WQOR spent, replay rejected, expired rejected, wrong signer rejected).
- Explorer: EVM transaction hashes open directly on the Testnet explorer.

## Repository layout

```
index.html        Board, Launch, More
trade.html        Swap
wallet.html       Wallet
docs.html         Public docs
logo.png          Brand mark
lib/common.js     Constants, EIP-712 domain and types, validation, window check, queue, seed helper
api/relay.js      Signed launch intake
api/status.js     Window and request status
api/process.js    Queue processor
api/swap.js       Signed swap intake
api/faucet.js     WQOR allowance
api/upload.js     Token image intake
contracts/        Solidity sources (MemeFactoryV2.sol; v3 sources are provided separately)
scripts/          Test and deploy scripts
docs/PROGRESS.md  Progress log, decisions, open issues, next steps
LICENSE           MIT
AI_USAGE.md       How AI tools were used in this project
```

## Known limits

- **No audit.** Testnet only.
- **Relayer holds the owner key** in its environment. Any relayer compromise moves its funds. A dedicated testnet account with a small balance is planned.
- **Rate limits are in memory** and reset when a serverless instance restarts. Persistent limits are planned.
- **Nonce handling** for sequential relayer submissions has a race condition. It is open (I9).
- **Native QOR transfers** are not in history, because they emit no logs.
- **Proofkick and other v2 tokens** have no pool and cannot be traded.
- **The 0.3% swap fee and price impact** are charged by design. The fee stays in the pool.
- **Image storage** depends on the Vercel Blob store being connected to the project.
- **Window is opened manually** until scheduled opening is confirmed.
- **Account endpoint** response format and whether it takes a `qor1` address are unconfirmed.

## Roadmap

1. Relaunch Proofkick on v3 so it can be traded.
2. Live test of the Wallet, Trade, and onboarding flows on mobile.
3. Native QOR as the default wallet account: balances and transfers first.
4. Native QOR transfer history, once a source is confirmed.
5. Liquidity: add-liquidity needs a contract change and a new deployment.
6. Analytics: price and volume from pool events, cached per token.
7. Relayer hardening: a dedicated account, persistent rate limits, and nonce management.

## Built for

QoreChain Build Before Q-Day hackathon. Submissions close 2 December 2026, 23:59 UTC.

## License

MIT. See `LICENSE`.
## Security

- QCAI stage 1 audit: [docs/QCAI-stage1.md](docs/QCAI-stage1.md)
- QCAI stage 2 remediation status: [docs/QCAI-stage2.md](docs/QCAI-stage2.md)
- Chapter close: [docs/CHAPTER-CLOSE.md](docs/CHAPTER-CLOSE.md)

PQC authorization applies to launches through MemeFactoryV4 only; the deployed MemeFactoryV3 remains capable of creating tokens without the PQC authorization check.
