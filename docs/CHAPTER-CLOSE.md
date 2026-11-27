# QCAI chapter close

Date: 26 November 2026
Repository: https://github.com/Collinxweb/Reqo

## Final status

| Finding | Final status |
|---|---|
| F-01 (High) | Mitigated in the app. Open on-chain. Scope stated. |
| F-02 (Low) | Open by design. Duplicate tickers allowed, with warning. |
| F-03 (Informational) | Documented. |

## Contracts

- MemeFactoryV4: 0xcD9eAC95a40FC237a634BB792bE44e899B9d0F57
- MemeFactoryV3: 0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f (legacy, no PQC check)
- WQOR: 0xF78c2cC7dc1B9ae52403868dD2097732Abfca665

## First V4 launch (user-supplied)

- Token: 0xb23E095B1EA613048B257247D6A6BDf1583CED3D
- Pool: 0x9cfcC62597078cD284F6adc32D0A221fa74BB86B
- Approve: 0x91656b25d3243483823980bda59bbaaaec3f47907895d416b12f27303e69042b
- Create: 0x1b009044057f5ae3359ec2230614a3f03199c93b2b977b2d6d2984bb261ef928

## Diana results (user-supplied, 26 November 2026)

- pqcKeyStatus, unregistered account: false, 0, 0x, false.
- pqcVerify, official vector 0: true. Tampered message: false.
- One pqcVerify call: 311,540 gas.

## Test evidence

- ReqoV4Test: 14 of 14 passed (user-supplied, commit be508c8).
- MlDsaVectorsTest: 4 of 4 passed (user-supplied, see stage 1 close-out note).

## Known limits

- The V3 factory bypass (F-01) cannot be removed on-chain.
- Duplicate tickers (F-02).
- Precompile behaviour is assumed to match documentation beyond the recorded checks.
- Deployed bytecode equivalence not verified.

## Scope

PQC authorization applies to launches through MemeFactoryV4 only; the deployed MemeFactoryV3 remains capable of creating tokens without the PQC authorization check.

The chapter is closed for submission. Stage 2 review by QCAI is still pending and is not claimed here.
