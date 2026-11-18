// Reqo swap relayer (Vercel function). Takes a trader's signed permit and swap intent,
// checks them, and submits pool.swap from the relayer account. The trader sends no transaction.

const C = require("../lib/common");
const { ethers } = C;

const FACTORY_V3 = "0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f";
const FACTORY_V3_ABI = ["function poolOf(address) view returns (address)"];
const POOL_ABI = [
  "function swap((address trader,bool buy,uint256 amountIn,uint256 minOut,uint256 nonce,uint256 deadline) s, bytes signature, uint256 permitDeadline, uint8 v, bytes32 r, bytes32 sv) returns (uint256)",
  "function nonceUsed(address,uint256) view returns (bool)",
];
const INTENT_TYPES = { Swap: [
  { name: "trader", type: "address" }, { name: "buy", type: "bool" },
  { name: "amountIn", type: "uint256" }, { name: "minOut", type: "uint256" },
  { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
] };
const MAX_PER_HOUR = 10;
const hits = new Map();

function rateOk(addr) {
  const now = Date.now();
  const list = (hits.get(addr) || []).filter((t) => now - t < 3600000);
  if (list.length >= MAX_PER_HOUR) { hits.set(addr, list); return false; }
  list.push(now); hits.set(addr, list); return true;
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const { token, pool, intent, intentSig, permit } = body;
    if (!ethers.isAddress(token) || !ethers.isAddress(pool)) throw new Error("bad token or pool address");
    if (!intent || !ethers.isAddress(intent.trader)) throw new Error("bad intent");
    for (const k of ["amountIn", "minOut", "nonce", "deadline"]) {
      if (!/^\d+$/.test(String(intent[k]))) throw new Error("bad intent " + k);
    }
    if (typeof intent.buy !== "boolean") throw new Error("bad intent buy flag");
    if (BigInt(intent.amountIn) <= 0n) throw new Error("amount must be above zero");
    if (typeof intentSig !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(intentSig)) throw new Error("bad intent signature");
    if (!permit || !/^\d+$/.test(String(permit.deadline))) throw new Error("bad permit");
    if (!/^0x[0-9a-fA-F]{64}$/.test(permit.r) || !/^0x[0-9a-fA-F]{64}$/.test(permit.s)) throw new Error("bad permit signature");

    const now = Math.floor(Date.now() / 1000);
    if (Number(intent.deadline) < now) throw new Error("intent expired");
    if (Number(permit.deadline) < now) throw new Error("permit expired");

    const trader = ethers.getAddress(intent.trader);
    if (!rateOk(trader.toLowerCase())) return res.status(429).json({ error: "too many trades from this address, try later" });

    const { wallet } = C.relayerFactory();
    const factory = new ethers.Contract(FACTORY_V3, FACTORY_V3_ABI, wallet.provider);
    const registered = await factory.poolOf(token);
    if (ethers.getAddress(registered) !== ethers.getAddress(pool)) throw new Error("pool is not registered for this token");

    const domain = { name: "Reqo Pool", version: "1", chainId: 9800, verifyingContract: ethers.getAddress(pool) };
    const signer = ethers.verifyTypedData(domain, INTENT_TYPES, intent, intentSig);
    if (signer.toLowerCase() !== trader.toLowerCase()) throw new Error("intent signature does not match trader");

    const poolC = new ethers.Contract(ethers.getAddress(pool), POOL_ABI, wallet);
    if (await poolC.nonceUsed(trader, intent.nonce)) throw new Error("nonce used");

    const win = await C.windowStatus();
    if (!win.live) return res.status(503).json({ error: "relayer window is closed. Try again when it opens." });

    const tx = await poolC.swap(
      { trader, buy: intent.buy, amountIn: intent.amountIn, minOut: intent.minOut, nonce: intent.nonce, deadline: intent.deadline },
      intentSig,
      permit.deadline,
      permit.v,
      permit.r,
      permit.s
    );
    return res.status(200).json({ txHash: tx.hash, trader, pool: ethers.getAddress(pool) });
  } catch (e) {
    return res.status(400).json({ error: e.shortMessage || e.message });
  }
};
