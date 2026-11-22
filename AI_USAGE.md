# AI usage

This file describes how AI tools were used in Reqo, for the QoreChain Build Before Q-Day submission.

## 1. AI used to build Reqo

- **Claude (Anthropic)** was used to draft and revise code, the design prototype, the progress log, and this documentation, in conversation with the developer (Collins).
- The developer read, ran, and deployed every change. Contract behaviour was verified on QoreChain Diana testnet with real transactions, not only by reading generated code.
- Generated code was not accepted without a check. Examples: the EIP-712 signatures were checked against the contract's digest, the constant-product quote was compared with an independent calculation, and the signed swap was tested with eight checks, including replay, expiry and wrong-signer cases.
- Where the AI's suggestions were wrong, they were corrected during testing. Examples recorded in `docs/PROGRESS.md` include a wrong explorer URL format, a wrong assumption about a chain endpoint, and a relayer design that was removed.

## 2. AI inside the product: Reqo AI

Reqo AI is a chat assistant on the Launch and Trade flows. It runs on the Groq API (free tier), using the model `openai/gpt-oss-120b`.

What it does:
- Turns a short description into a complete token draft: name, ticker, supply and description.
- Turns a buy or sell request, with a ticker or contract address and an amount, into a trade request.

What it does not do:
- It never signs, sends or submits any transaction. Every launch and trade requires the user to confirm in their own wallet.
- It cannot see images. The model on the Groq key does not accept images, so an uploaded image is attached to the token by the app, not read by the AI.
- It does not have access to wallets, keys, balances or contracts. The browser sends it the chat text only.

Safeguards:
- The server validates every draft and trade before the app shows it. Invalid fields are rejected with a message.
- A trade request is checked against the factory's token list before the Trade screen opens. An unknown ticker or address is refused.
- The Groq key is held only on the server, and error messages mask it.
- Requests are rate limited per network.

## 3. Known limits

- The model can make mistakes in wording or suggested names. Users must check the review screen before signing.
- The AI's suggestions are not financial advice. Reqo is testnet software.
- No AI component has been audited.

## 4. Data sent to the AI provider

Only the chat text the user types, and a note that an image is attached. No wallet addresses, balances or keys are sent to Groq.
