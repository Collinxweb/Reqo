// Reqo WQOR faucet (Vercel function). Sends a fixed WQOR allowance from the relayer account
// to a trader's address. Each address can receive up to CAP_PER_ADDRESS in total.
// Needs the relayer window to be live, because the relayer account sends the transfer.

const C = require("../lib/common");
const { ethers } = C;

const WQOR = "0xF78c2cC7dc1B9ae52403868dD2097732Abfca665";
const WQOR_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function deposit() payable",
  "function transfer(address to, uint256 value) returns (bool)",
];
const GRANT = ethers.parseEther("5");
const CAP_PER_ADDRESS = ethers.parseEther("5");
const MAX_PER_HOUR_IP = 10;

const ipHits = new Map();
const memGranted = new Map();

function ipOk(ip) {
  const now = Date.now();
  const hits = (ipHits.get(ip) || []).filter((t) => now - t < 3600000);
  if (hits.length >= MAX_PER_HOUR_IP) {
    ipHits.set(ip, hits);
    return false;
  }
  hits.push(now);
  ipHits.set(ip, hits);
  return true;
}

async function alreadyGranted(addr) {
  if (C.queueEnabled()) {
    const v = await C.kv("GET", "faucet:" + addr);
    return BigInt(v || "0");
  }
  return memGranted.get(addr) || 0n;
}

async function recordGrant(addr, total) {
  if (C.queueEnabled()) await C.kv("SET", "faucet:" + addr, total.toString());
  else memGranted.set(addr, total);
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    if (!ethers.isAddress(body.address)) throw new Error("bad address");
    const addr = ethers.getAddress(body.address);

    const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
    if (!ipOk(ip)) return res.status(429).json({ error: "too many requests from this network, try again later" });

    const done = await alreadyGranted(addr);
    if (done + GRANT > CAP_PER_ADDRESS)
      return res.status(429).json({ error: "this address already received its WQOR allowance" });

    const win = await C.windowStatus();
    if (!win.live) return res.status(503).json({ error: "relayer window is closed. Try again when it opens." });

    const { wallet } = C.relayerFactory();
    const wqor = new ethers.Contract(WQOR, WQOR_ABI, wallet);

    const ownerBal = await wqor.balanceOf(wallet.address);
    if (ownerBal < GRANT) {
      const wrap = await wqor.deposit({ value: GRANT - ownerBal });
      await wrap.wait();
    }

    const tx = await wqor.transfer(addr, GRANT);
    await recordGrant(addr, done + GRANT);
    return res.status(200).json({ txHash: tx.hash, address: addr, amount: "5" });
  } catch (e) {
    return res.status(400).json({ error: e.shortMessage || e.message });
  }
};
