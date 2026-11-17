// Reqo v2 test script. Run in ~/deploy with abi-v2.json present.
// Owner key (PK) is the relayer and pays gas. The user and attacker keys are
// random throwaway wallets that never receive funds; they only sign messages.
//
// Usage:
//   read -s -p "Owner private key: " PK; echo
//   FACTORY=0xYourV2Address PK="$PK" node test-v2.js
//   unset PK
//   history -c

const { ethers } = require("ethers");
const fs = require("fs");

const RPC = "https://evm-testnet.qore.host";
const FACTORY = process.env.FACTORY;
if (!FACTORY) throw new Error("set FACTORY=0x... before running");
if (!process.env.PK) throw new Error("PK not set (use the read -s step)");

const provider = new ethers.JsonRpcProvider(RPC, 9800, { staticNetwork: true });
const relayer = new ethers.Wallet(process.env.PK, provider);
const user = ethers.Wallet.createRandom();
const attacker = ethers.Wallet.createRandom();
const abi = JSON.parse(fs.readFileSync("abi-v2.json", "utf8"));
const factory = new ethers.Contract(FACTORY, abi, relayer);

const domain = {
  name: "Reqo MemeFactory",
  version: "2",
  chainId: 9800,
  verifyingContract: FACTORY,
};
const types = {
  CreateToken: [
    { name: "creator", type: "address" },
    { name: "name", type: "string" },
    { name: "symbol", type: "string" },
    { name: "supply", type: "uint256" },
    { name: "description", type: "string" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

const now = Math.floor(Date.now() / 1000);
function request(over = {}) {
  return {
    creator: user.address,
    name: "Relay Cat",
    symbol: "RCAT",
    supply: 1000,
    description: "relayed",
    nonce: 1,
    deadline: now + 3600,
    ...over,
  };
}

let pass = 0, fail = 0;
function check(label, ok, detail = "") {
  ok ? pass++ : fail++;
  console.log((ok ? "PASS " : "FAIL ") + label + (detail ? "  [" + detail + "]" : ""));
}

async function expectRevert(label, promise, reason) {
  try {
    await promise;
    check(label, false, "did not revert");
  } catch (e) {
    const msg = e.shortMessage || e.message || String(e);
    check(label, msg.includes(reason), msg);
  }
}

(async () => {
  console.log("relayer:", relayer.address);
  console.log("user (signer, unfunded):", user.address);

  // 0. digest matches the EIP-712 hash computed locally
  const r0 = request();
  const localDigest = ethers.TypedDataEncoder.hash(domain, types, r0);
  const contractDigest = await factory.digest(r0);
  check("digest matches local EIP-712 hash", localDigest === contractDigest, contractDigest);

  // 1. expired deadline is rejected (static call, no transaction sent)
  const rExp = request({ nonce: 10, deadline: now - 60 });
  await expectRevert(
    "expired deadline rejected",
    factory.createTokenFor.staticCall(rExp, await user.signTypedData(domain, types, rExp)),
    "expired"
  );

  // 2. signature from a different key is rejected
  const rBad = request({ nonce: 11 });
  await expectRevert(
    "wrong signer rejected",
    factory.createTokenFor.staticCall(rBad, await attacker.signTypedData(domain, types, rBad)),
    "bad signature"
  );

  // 3. zero supply is rejected
  const rZero = request({ nonce: 12, supply: 0 });
  await expectRevert(
    "zero supply rejected",
    factory.createTokenFor.staticCall(rZero, await user.signTypedData(domain, types, rZero)),
    "zero supply"
  );

  // 4. valid signed request creates the token for the signer
  const before = Number(await factory.tokenCount());
  const r1 = request({ nonce: 1 });
  const sig1 = await user.signTypedData(domain, types, r1);
  const tx = await factory.createTokenFor(r1, sig1);
  console.log("createTokenFor tx:", tx.hash);
  await tx.wait();

  const after = Number(await factory.tokenCount());
  check("tokenCount increased by 1", after === before + 1, before + " -> " + after);

  const tokenAddr = await factory.tokens(before);
  const creatorOk = (await factory.creatorOf(tokenAddr)).toLowerCase() === user.address.toLowerCase();
  check("creatorOf is the signer, not the relayer", creatorOk, tokenAddr);

  const token = new ethers.Contract(
    tokenAddr,
    [
      "function balanceOf(address) view returns (uint256)",
      "function decimals() view returns (uint8)",
      "function name() view returns (string)",
      "function symbol() view returns (string)",
    ],
    provider
  );
  const bal = await token.balanceOf(user.address);
  check("signer holds 1000 whole tokens (1000e18 units)", bal === 1000n * 10n ** 18n, bal.toString());
  check("decimals is 18", Number(await token.decimals()) === 18);
  check("name and symbol match request", (await token.name()) === "Relay Cat" && (await token.symbol()) === "RCAT");

  // 5. replaying the same signed request is rejected
  await expectRevert(
    "replay rejected",
    factory.createTokenFor.staticCall(r1, sig1),
    "nonce used"
  );

  console.log(`\nResult: ${pass} passed, ${fail} failed`);
  if (fail > 0) process.exitCode = 1;
})().catch((e) => {
  console.error("ERROR:", e.shortMessage || e.message);
  process.exitCode = 1;
});
