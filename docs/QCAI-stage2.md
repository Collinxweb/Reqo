# QCAI stage 2: remediation status

Date: 26 November 2026
Repository: https://github.com/Collinxweb/Reqo

## Remediation table

| ID | Severity | Fix or mitigation | Evidence | Status |
|---|---|---|---|---|
| F-01 | High | Tokens from MemeFactoryV3 are labelled "Legacy, no PQC check" in the Dashboard, Trade picker and Wallet. | App source `index.html`, release v4.16.0 onward. Source is the live file; the commit that added it is not recorded here. | Mitigated in the app. Open on-chain: MemeFactoryV3 at 0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f still allows launches without the check. |
| F-02 | Low | Duplicate tickers are allowed. The Reqo AI check warns about existing tickers and names. | App source, Reqo AI check, release v4.14.0 onward. | Open by design. No uniqueness guarantee. |
| F-03 | Informational | Donations to a pool do not change prices. Documented as a known behaviour. | Pool source, `src/ReqoV3.sol`. | Documented. No code change planned. |

## Scope

PQC authorization applies to launches through MemeFactoryV4 only; the deployed MemeFactoryV3 remains capable of creating tokens without the PQC authorization check.

## Open items

1. F-01 cannot be fixed on-chain. The only full fix is a future deployment that retires MemeFactoryV3. Until then, the labels and this scope sentence are the controls.
2. Confirm that the deployed bytecode of MemeFactoryV4 matches `src/ReqoV4.sol`. Not verified.
3. Precompile behaviour beyond the recorded checks is an assumption.
4. Stage 2 review by QCAI is pending.

## Verdict for submission

No finding allows funds to be taken from the factory or the pools. The launch gate applies to MemeFactoryV4 only, and that scope is stated in the README and this report.
