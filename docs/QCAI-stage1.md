# QCAI Stage 1: Reqo contract security audit

Repository: https://github.com/Collinxweb/Reqo
Network: QoreChain testnet `qorechain-diana` (EVM chain ID 9800)
Status: stage 1 report. No code was changed and no tests were run in this stage.

## Scope

- `src/ReqoV4.sol`: MemeFactoryV4, deployed at `0xcD9eAC95a40FC237a634BB792bE44e899B9d0F57`.
- `src/ReqoV3.sol`: WQOR (`0xF78c2cC7dc1B9ae52403868dD2097732Abfca665`), MemeTokenV3, PoolV3, and MemeFactoryV3 (`0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f`).

Out of scope: the front end, `api/` routes, tests, and QoreChain's precompiles at `0x…0A01` and `0x…0A02`.

This is a source review of the default-branch files. It does not verify that the deployed bytecode matches these files.

## Verdict

High-severity architectural bypass. The V4 launch gate enforces its checks inside V4. The V3 factory, which is still deployed and in scope, exposes public token creation without the PQC check. The system therefore does not enforce PQC authorization for every launch. No critical reserve-drain vulnerability was found in the reviewed pool source.

## Findings

| ID | Severity | Location | Description and impact | Suggested fix |
|---|---|---|---|---|
| F-01 | High | ReqoV3.sol, MemeFactoryV3.createToken() and createTokenFor() | Both public paths create tokens without the V4 PQC gate. Anyone able to pay the seed can launch through V3. V3 also accepts non-ASCII names and arbitrary ticker characters. This does not forge a V4 launch, but it bypasses any claim that all launches require proven PQC ownership. | Retire or disable V3 creation, or have every consumer recognise only V4 factory provenance. |
| F-02 | Low | ReqoV4.sol, _checkFields() and _create() | No symbol uniqueness check. Several launches can share a ticker, so users or integrations that rely on symbols can misidentify assets. | If uniqueness is promised, add a canonical symbol registry. Otherwise identify assets by chain and address. |
| F-03 | Informational | ReqoV3.sol, PoolV3.seed() and swap() | Reserves track accounted amounts, not balances. Direct donations create a surplus without changing quotes. This does not change the price or provide a withdrawal path. | Document accounted reserves separately from balances, and define a surplus policy. |

## Foundry reproduction (designs, not executed)

- F-01 `test_V3BypassesV4Gate`: deploy WQOR and MemeFactoryV3, wrap 10 QOR, approve the factory, call `createToken("Unverified", "BAD!", 1, "")`, and assert the token exists with no PQC precompile interaction. Repeat with `createTokenFor()` and a valid ECDSA signature.
- F-02 `test_DuplicateTickerAccepted`: mock successful V4 precompile responses, fund and approve the seed, create two launches with the same symbol and different nonces, and assert distinct addresses with equal symbols.
- F-03 `test_DonationDoesNotChangeQuote`: seed a pool, record reserves and a quote, transfer extra tokens directly to the pool, and assert the quote and reserves are unchanged while the balance exceeds `tokenReserve`.

## Checks completed

- V4 binds the signed message to the creator, a per-creator nonce, the deadline, chain ID, factory address, name, symbol, supply and description hash. A used nonce cannot be reused by the same creator. Expired requests revert.
- The key-status checks require registration, algorithm ID 1, possession proof, and equality with the submitted public key. Failed calls and undecodable results revert. The verify call requires exactly 32 bytes and decodes a Boolean. Missing precompiles that return empty data cannot produce success.
- V4 uses `nonReentrant`. The seed transfer and pool seeding are atomic with creation. Supply multiplication is bounded. The token has no transfer hooks.
- Pool swaps bind the trader, direction, amount, minimum output, nonce and deadline in EIP-712. The domain separates pools and chains. Output goes to the signed trader.
- A front-runner submitting a permit first does not block the swap, because `swap()` skips `permit()` when the allowance is sufficient. The signed intent is still required.
- The fee-adjusted quote rounds output down. Zero output and insufficient liquidity revert. The post-swap invariant is checked. PoolV3 has no reserve-withdrawal path. WQOR withdrawal burns before sending native currency.
- V4 bounds names, symbols and descriptions. V3 does not.
- No unbounded iteration or persistent gas-griefing mechanism was found.

## Assumptions and limits

The V4 conclusions assume `pqcKeyStatus` correctly binds the registered key and possession proof to the account, and that `pqcVerify` returns true only for a valid ML-DSA-87 signature over the exact message. The precompiles were out of scope and were not independently verified. A precompile that returned a validly encoded `true` for an invalid signature could not be detected by these contracts.

## Remediation

The principal fix is to eliminate the V3 bypass or enforce canonical V4 provenance. Until then, describe PQC authorization as a property of launches through MemeFactoryV4 only, not of the whole Reqo launch ecosystem.
