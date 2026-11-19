// Reqo v2.1.0 scheduler. Called every minute by an external cron service.
// Requires header x-cron-secret (or ?secret=) matching CRON_SECRET.
// Submits up to 5 queued requests per call, only while the window is live.
// Optional: ?opensAt=<ISO time> stores the next planned opening time in KV, so no redeploy is needed.

const C = require("../lib/common");

module.exports = async (req, res) => {
  const url = new URL(req.url, "http://x");
  const secret = req.headers["x-cron-secret"] || url.searchParams.get("secret");
  if (!process.env.CRON_SECRET || secret !== process.env.CRON_SECRET)
    return res.status(401).json({ error: "unauthorized" });

  try {
    const setOpensAt = url.searchParams.get("opensAt");
    if (setOpensAt) {
      const t = Date.parse(setOpensAt);
      if (Number.isNaN(t)) return res.status(400).json({ error: "bad opensAt" });
      const iso = new Date(t).toISOString();
      await C.kv("SET", "config:opensAt", iso);
      return res.status(200).json({ opensAt: iso });
    }

    if (!C.queueEnabled()) return res.status(200).json({ processed: 0, note: "queue not configured" });

    const win = await C.windowStatus();
    if (!win.live) return res.status(200).json({ processed: 0, windowLive: false });

    const now = Math.floor(Date.now() / 1000);
    const { wallet, factory } = C.relayerFactory();
    const ids = (await C.queuedIds()).slice(0, 5);
    const results = [];

    for (const id of ids) {
      const rec = await C.getRecord(id);
      if (!rec || rec.status !== "queued") {
        await C.dequeue(id);
        continue;
      }

      if (rec.deadline < now) {
        rec.status = "expired";
        await C.putRecord(id, rec);
        await C.dequeue(id);
        results.push({ id, status: "expired" });
        continue;
      }

      try {
        const r = rec.request;
        if (C.verify(r, rec.signature) !== r.creator) throw new Error("bad signature");
        if (await factory.nonceUsed(r.creator, r.nonce)) throw new Error("nonce used");
        await C.ensureSeed(wallet);
        const tx = await factory.createTokenFor(r, rec.signature);
        rec.status = "submitted";
        rec.txHash = tx.hash;
        results.push({ id, status: "submitted", txHash: tx.hash });
      } catch (e) {
        rec.status = "error";
        rec.error = C.rpcError(e);
        results.push({ id, status: "error", error: rec.error });
      }

      await C.putRecord(id, rec);
      await C.dequeue(id);
    }

    return res.status(200).json({ windowLive: true, processed: results.length, results });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};
