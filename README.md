# Reqo

**Problem:** memecoin launches on public chains can be created by anyone, with no proof that the creator controls the key they claim.

**Solution:** Reqo launches tokens through a factory that only accepts a request signed by the creator's registered post-quantum (ML-DSA-87) key, verified on-chain by QoreChain's native precompile.

> **Testnet only.** Reqo runs on QoreChain testnet "Diana". No real funds are used.

| | |
|---|---|
| Live app | https://reqo-seven.vercel.app |
| Network | QoreChain testnet "qorechain-diana" |
| Chain ID | 9800 (0x2648) |
| RPC | https://evm-testnet.qore.host |

## Scope

PQC authorization applies to launches through MemeFactoryV4 only; the deployed MemeFactoryV3 remains capable of creating tokens without the PQC authorization check.

Reqo does not claim that the whole launch ecosystem is post-quantum gated. Legacy V3 tokens are labelled in the app.

## Why QoreChain

- **Native PQC precompiles.** The launch gate calls `pqcVerify` (ML-DSA-87) and `pqcKeyStatus` (registered key and possession proof) at QoreChain's built-in addresses.
- **QoreX wallet.** The creator signs the request with the account's ML-DSA-87 key through QoreX. MetaMask cannot produce this signature, so launches are disabled there.
- **V4 authorization flow.** The signed message is built on-chain from the request fields, so the signer approves exactly what is created.

## Recorded Diana results (user-supplied, 26 November 2026, not reproduced by the agent)

- `pqcKeyStatus` for an unregistered account returns `false, 0, 0x, false`.
- `pqcVerify` returns `true` for QoreChain's official ML-DSA-87 vector 0, and `false` for the same message with its last byte changed.
- One `pqcVerify` call estimates at 311,540 gas.

## Live example: first V4 launch

- Token: `0xb23E095B1EA613048B257247D6A6BDf1583CED3D`
- Pool: `0x9cfcC62597078cD284F6adc32D0A221fa74BB86B`
- Approve transaction: `0x91656b25d3243483823980bda59bbaaaec3f47907895d416b12f27303e69042b`
- Create transaction: `0x1b009044057f5ae3359ec2230614a3f03199c93b2b977b2d6d2984bb261ef928`
- Explorer links: UNVERIFIED. Confirm each link opens before publishing.

## User journey

1. Connect QoreX on Diana.
2. Review a launch. Sign and create is enabled only in QoreX. MetaMask cannot sign with the PQC key, so the review explains why.
3. QoreX signs the request. The approve and create transactions are confirmed in the wallet.
4. The token appears on the Dashboard with the PQC launch label. Legacy V3 tokens show "Legacy, no PQC check".
5. Buy or sell through the pool. Balances update after the trade confirms.

Demo video: UNVERIFIED. Add the link once recorded. The simulated walkthrough is not evidence of on-chain behaviour.

## Architecture

Source: `index.html`. Launch path: the review's Sign button (`dlg-sign` handler) calls `createToken` on MemeFactoryV4 only. Trade and wallet reads use both factories, labelling V3 tokens "Legacy, no PQC check". The V3 factory has no write path in the app.

```
Browser (index.html) ──► QoreX wallet ──► signs request (off-chain key)
      │                       │
      │ reads                 │ submits transactions
      ▼                       ▼
QoreChain RPC ──► MemeFactoryV4 ──► pqcKeyStatus / pqcVerify (precompiles)
                       │
                       ├──► MemeTokenV3 + PoolV3 (per token)
                       └──► WQOR (wrapped QOR, seed and trades)

MemeFactoryV3 (legacy) ──► creates tokens without the PQC check
```

Off-chain: the static front end and the wallet. On-chain enforcement: the V4 factory's checks. The V3 factory is on-chain and not gated.

## Contracts

| Contract | Address | Purpose | Version | Explorer |
|---|---|---|---|---|
| WQOR | `0xF78c2cC7dc1B9ae52403868dD2097732Abfca665` | Wrapped QOR for seeds and trades | Diana | UNVERIFIED |
| MemeFactoryV4 | `0xcD9eAC95a40FC237a634BB792bE44e899B9d0F57` | PQC-gated launches | v4 | UNVERIFIED |
| MemeFactoryV3 | `0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f` | Legacy launches, no PQC check | v3 | UNVERIFIED |

Deployed bytecode matching the source in this repository is not verified.

## Security model

- **Signed fields:** domain tag, chain ID, factory address, creator, nonce, deadline, name, symbol, supply and description hash. The contract builds the message itself.
- **Nonce and deadline:** a nonce can be used once per creator, and expired requests revert.
- **Key checks:** the creator's key must be registered, algorithm 1, possession proven, and equal to the submitted key.
- **Fail closed:** a failed precompile call or malformed result reverts.
- **Precompile trust:** correctness of `pqcVerify` and `pqcKeyStatus` is an assumption, checked only against the recorded results above.
- **V3 bypass:** open on-chain. Mitigated in the app by legacy labels. See the QCAI stage 1 report.

## Test evidence

| Suite | Count | Source | Commit |
|---|---|---|---|
| ReqoV4Test | 14 of 14 passed | User-supplied terminal output | be508c8 |
| MlDsaVectorsTest | 4 of 4 passed | User-supplied terminal output | 06ddae5 or later |
| Test declarations | 14 and 4 | Static count in the files | main |

The agent did not run these tests. Reproduce with `forge test` (see Local setup).

## Known limitations

- **V3 authorization bypass (F-01).** Cannot be removed on-chain without a new deployment.
- **Duplicate tickers (F-02).** The Reqo launch flow blocks a ticker already used by any token from either factory. The contracts do not enforce this: MemeFactoryV4 and the V3 factory accept duplicate tickers when called directly, so this is an app-level control only.
- **Bytecode equivalence.** Not verified.
- **Audit status.** The QCAI stage 1 document is a source review. It is not a completed independent audit, and stage 2 is pending.

## Local setup

```bash
git clone https://github.com/Collinxweb/Reqo && cd Reqo
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge test
```

Environment variable names only; never commit values: `RPC_URL`, `PRIVATE_KEY` (deployment only).

## Documents

- [QCAI stage 1 audit](docs/QCAI-stage1.md)
- [QCAI stage 2 remediation status](docs/QCAI-stage2.md)
- [Chapter close](docs/CHAPTER-CLOSE.md)
- [Progress log](docs/PROGRESS.md)
