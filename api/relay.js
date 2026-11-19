// Reqo v2.1.0 relayer. Verifies a user's EIP-712 signed request.
// If the window is live, it submits now. If not, it queues the request (HTTP 202)
// for process.js to submit when the window opens.

const C = require("../lib/common");

const MAX_PER_HOUR = 5;
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

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const r = C.parseRequest(body.request);
    const sig = body.signature;
    if (typeof sig !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(sig)) throw new Error("bad signature format");

    const now = Math.floor(Date.now() / 1000);
    if (Number(r.deadline) < now) throw new Error("expired");
    if (C.verify(r, sig) !== r.creator) throw new Error("bad signature");

    const id = C.ethers.id(sig);

    // Same request already known: return its current status (makes retries safe).
    if (C.queueEnabled()) {
      const existing = await C.getRecord(id);
      if (existing) return res.status(200).json(C.publicView(id, existing));
    }

    const { wallet, factory } = C.relayerFactory();
    if (await factory.nonceUsed(r.creator, r.nonce)) throw new Error("nonce used");

    if (!rateOk(r.creator.toLowerCase()))
      return res.status(429).json({ error: "rate limit: 5 requests per hour per address" });

    const win = await C.windowStatus();

    if (!win.live) {
      if (!C.queueEnabled()) return res.status(503).json({ error: "relayer window closed" });
      const opensAt = await C.getOpensAt();
      const rec = { status: "queued", request: r, signature: sig, deadline: Number(r.deadline) };
      await C.putRecord(id, rec);
      await C.enqueue(id);
      return res.status(202).json({ ...C.publicView(id, rec), opensAt });
    }

    await C.ensureSeed(wallet);
    const tx = await factory.createTokenFor(r, sig);
    if (C.queueEnabled()) {
      await C.putRecord(id, { status: "submitted", txHash: tx.hash, deadline: Number(r.deadline) });
    }
    return res.status(200).json({ id, status: "submitted", txHash: tx.hash, creator: r.creator });
  } catch (e) {
    return res.status(400).json({ error: C.rpcError(e) });
  }
};
