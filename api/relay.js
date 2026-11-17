// Reqo v2 relayer (Vercel serverless function).
// Receives an EIP-712 signed creation request from a user, verifies it,
// and submits createTokenFor from the owner account (OWNER_PK env var).
// Status: NOT YET TESTED LIVE. See progress doc section 12.

const { ethers } = require("ethers");

const RPC = "https://evm-testnet.qore.host";
const CHAIN_ID = 9800;
const FACTORY = "0xbEe5D528b86fDe7bd68a1330B4A76E838390d356";
const RELAYER_QOR = "qor1cd7f0lv83huuunz6dgk6n5eu3mt8qzsmm35g8j";
const WINDOW_URL = `https://api-testnet.qore.host/qorechain/pqc/v1/evm_window/${RELAYER_QOR}`;
const MAX_PER_HOUR = 5;

const ABI = [
  "function createTokenFor((address creator,string name,string symbol,uint256 supply,string description,uint256 nonce,uint256 deadline) r, bytes signature) returns (address)",
  "function nonceUsed(address creator, uint256 nonce) view returns (bool)",
];

const domain = {
  name: "Reqo MemeFactory",
  version: "2",
  chainId: CHAIN_ID,
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

const provider = new ethers.JsonRpcProvider(RPC, CHAIN_ID, { staticNetwork: true });
const relayer = new ethers.Wallet(process.env.OWNER_PK || "0x" + "00".repeat(32), provider);
const factory = new ethers.Contract(FACTORY, ABI, relayer);

// Soft rate limit per creator address. Resets when the serverless instance restarts.
const recent = new Map();
function rateOk(addr) {
  const now = Date.now();
  const hits = (recent.get(addr) || []).filter((t) => now - t < 3600000);
  if (hits.length >= MAX_PER_HOUR) {
    recent.set(addr, hits);
    return false;
  }
  hits.push(now);
  recent.set(addr, hits);
  return true;
}

async function windowLive() {
  const r = await fetch(WINDOW_URL);
  const j = await r.json();
  return j.live === true && Number(j.remaining_txs) > 0;
}

function parseRequest(r) {
  if (!r || typeof r !== "object") throw new Error("missing request");
  if (!ethers.isAddress(r.creator)) throw new Error("bad creator");
  if (typeof r.name !== "string" || Buffer.byteLength(r.name) < 1 || Buffer.byteLength(r.name) > 32)
    throw new Error("bad name");
  if (typeof r.symbol !== "string" || Buffer.byteLength(r.symbol) < 1 || Buffer.byteLength(r.symbol) > 10)
    throw new Error("bad symbol");
  if (typeof r.description !== "string" || Buffer.byteLength(r.description) > 280)
    throw new Error("bad description");
  for (const k of ["supply", "nonce", "deadline"]) {
    if (!/^\d+$/.test(String(r[k]))) throw new Error("bad " + k);
  }
  const supply = BigInt(r.supply);
  if (supply < 1n || supply > 1000000000000n) throw new Error("supply out of range");
  return {
    creator: ethers.getAddress(r.creator),
    name: r.name,
    symbol: r.symbol,
    supply: supply.toString(),
    description: r.description,
    nonce: String(r.nonce),
    deadline: String(r.deadline),
  };
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const r = parseRequest(body.request);
    const sig = body.signature;
    if (typeof sig !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(sig)) throw new Error("bad signature format");

    const now = Math.floor(Date.now() / 1000);
    if (Number(r.deadline) < now) throw new Error("expired");

    const signer = ethers.verifyTypedData(domain, types, r, sig);
    if (signer !== r.creator) throw new Error("bad signature");

    if (await factory.nonceUsed(r.creator, r.nonce)) throw new Error("nonce used");

    if (!rateOk(r.creator.toLowerCase()))
      return res.status(429).json({ error: "rate limit: 5 requests per hour per address" });

    if (!(await windowLive())) return res.status(503).json({ error: "relayer window closed" });

    // Gas is estimated before sending, so a reverting request is refused without spending gas.
    const tx = await factory.createTokenFor(r, sig);
    return res.status(200).json({ txHash: tx.hash, creator: r.creator });
  } catch (e) {
    return res.status(400).json({ error: e.shortMessage || e.message });
  }
};
