# Reqo (MemeFactory on QoreChain Diana testnet)

Static frontend for a memecoin factory on QoreChain testnet.

- Chain: qorechain-diana, EVM chain ID 9800, RPC https://evm-testnet.qore.host
- Factory: 0x6944168F50aCCBB602c519a0f85B17610E06594b

The page lists tokens created by the factory. The create button needs a wallet injected into the browser and an open EVM authorisation window on the account.

Known limits (v1):
- Supply is stored as raw units (no decimals applied).
- Testnet only, not audited.
