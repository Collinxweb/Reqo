// Shared config and helpers for the Reqo v2 relayer (Vercel functions).
// Queue storage uses Upstash REST (Vercel KV). Without it, the relayer refuses requests while the window is closed.

const { ethers } = require("ethers");

const RPC = "https://evm-testnet.qore.host";
const CHAIN_ID = 9800;
const FACTORY = "0x65353cD68F5f0E3e6FD3c578f1215E36dA25Ed8f";
const WQOR = "0xF78c2cC7dc1B9ae52403868dD2097732Abfca665";
const SEED = 10n * 10n ** 18n;
const WQOR_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function deposit() payable",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
];
const RELAYER_QOR = "qor1cd7f0lv83huuunz6dgk6n5eu3mt8qzsmm35g8j";
const WINDOW_URL = `https://api-testnet.qore.host/qorechain/pqc/v1/evm_window/${RELAYER_QOR}`;

const ABI = [
  "function createTokenFor((address creator,string name,string symbol,uint256 supply,string description,uint256 nonce,uint256 deadline) r, bytes signature) returns (address)",
  "function nonceUsed(address creator, uint256 nonce) view returns (bool)",
];

const domain = {
  name: "Reqo MemeFactory",
  version: "3",
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

function readProvider() {
  return new ethers.JsonRpcProvider(RPC, CHAIN_ID, { staticNetwork: true });
}

function readFactory() {
  return new ethers.Contract(FACTORY, ABI, readProvider());
}

function relayerFactory() {
  const wallet = new ethers.Wallet(process.env.OWNER_PK, readProvider());
  return { wallet, factory: new ethers.Contract(FACTORY, ABI, wallet) };
}

async function windowStatus() {
  const r = await fetch(WINDOW_URL);
  const j = await r.json();
  return {
    live: j.live === true && Number(j.remaining_txs) > 0,
    remainingBlocks: Number(j.remaining_blocks || 0),
    remainingTxs: Number(j.remaining_txs || 0),
  };
}

function parseRequest(r) {
  if (!r || typeof r !== "object") throw new Error("missing request");
  if (!ethers.isAddress(r.creator)) throw new Error("bad creator");
  const nameLen = Buffer.byteLength(String(r.name ?? ""));
  if (typeof r.name !== "string" || nameLen < 1 || nameLen > 32) throw new Error("bad name");
  const symLen = Buffer.byteLength(String(r.symbol ?? ""));
  if (typeof r.symbol !== "string" || symLen < 1 || symLen > 10) throw new Error("bad symbol");
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

function verify(r, sig) {
  return ethers.verifyTypedData(domain, types, r, sig);
}

function queueEnabled() {
  return !!(process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN);
}

async function kv(...cmd) {
  if (!queueEnabled()) throw new Error("queue storage not configured");
  const r = await fetch(process.env.KV_REST_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.KV_REST_API_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(cmd),
  });
  const j = await r.json();
  if (j.error) throw new Error(j.error);
  return j.result;
}

async function getRecord(id) {
  const raw = await kv("GET", "req:" + id);
  return raw ? JSON.parse(raw) : null;
}

function ttlFor(deadline) {
  const now = Math.floor(Date.now() / 1000);
  return Math.max(60, deadline - now + 86400);
}

async function putRecord(id, rec) {
  await kv("SET", "req:" + id, JSON.stringify(rec), "EX", String(ttlFor(rec.deadline)));
}

async function enqueue(id) {
  await kv("SADD", "queue", id);
}

async function dequeue(id) {
  await kv("SREM", "queue", id);
}

async function queuedIds() {
  return (await kv("SMEMBERS", "queue")) || [];
}

// Scheduled relayer windows, in UTC hours. Each window is planned to stay open for WINDOW_HOURS.
const SCHEDULE_UTC_HOURS = [1, 13];
const WINDOW_HOURS = 5;

// Next planned opening strictly after nowMs, as an ISO string.
function nextScheduledOpening(nowMs) {
  const d = new Date(nowMs);
  const base = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const candidates = [];
  for (const dayOffset of [0, 1]) {
    for (const h of SCHEDULE_UTC_HOURS) {
      candidates.push(base + dayOffset * 86400000 + h * 3600000);
    }
  }
  const next = candidates.filter((t) => t > nowMs).sort((a, b) => a - b)[0];
  return new Date(next).toISOString();
}

// Planned opening time: a manual override stored in KV (set through /api/process?opensAt=)
// if it is still in the future, otherwise the next scheduled window.
async function getOpensAt() {
  const now = Date.now();
  if (queueEnabled()) {
    const stored = await kv("GET", "config:opensAt");
    if (stored && Date.parse(stored) > now) return stored;
  }
  return nextScheduledOpening(now);
}

function publicView(id, rec) {
  return {
    id,
    status: rec.status,
    txHash: rec.txHash || null,
    error: rec.error || null,
    deadline: rec.deadline,
  };
}

// Every v3 launch pulls a 10 WQOR seed from the sender. Keep the relayer funded and approved.
async function ensureSeed(wallet) {
  const w = new ethers.Contract(WQOR, WQOR_ABI, wallet);
  const bal = await w.balanceOf(wallet.address);
  if (bal < SEED) await (await w.deposit({ value: SEED - bal })).wait();
  const al = await w.allowance(wallet.address, FACTORY);
  if (al < SEED) await (await w.approve(FACTORY, ethers.MaxUint256)).wait();
}

// Full revert or RPC message for logs and queue records (ethers wraps the real error).
function rpcError(e) {
  return (e && e.info && e.info.error && e.info.error.message) || (e && e.shortMessage) || (e && e.message) || String(e);
}

module.exports = {
  ethers,
  FACTORY,
  readFactory,
  relayerFactory,
  windowStatus,
  parseRequest,
  verify,
  queueEnabled,
  kv,
  getRecord,
  putRecord,
  enqueue,
  dequeue,
  queuedIds,
  getOpensAt,
  nextScheduledOpening,
  SCHEDULE_UTC_HOURS,
  WINDOW_HOURS,
  publicView,
  ensureSeed,
  rpcError,
};
