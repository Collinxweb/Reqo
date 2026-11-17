// Reqo v2.1.0 status. GET /api/status returns window and queue state.
// GET /api/status?id=... returns the status of one queued or submitted request.

const C = require("../lib/common");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  if (req.method !== "GET") return res.status(405).json({ error: "GET only" });

  try {
    const url = new URL(req.url, "http://x");
    const id = url.searchParams.get("id");

    if (id) {
      if (!C.queueEnabled()) return res.status(404).json({ error: "queue not configured" });
      const rec = await C.getRecord(id);
      if (!rec) return res.status(404).json({ error: "not found" });
      return res.status(200).json(C.publicView(id, rec));
    }

    const win = await C.windowStatus();
    const queueOn = C.queueEnabled();
    const opensAt = queueOn ? await C.getOpensAt() : process.env.WINDOW_OPENS_AT || null;
    const queued = queueOn ? (await C.queuedIds()).length : 0;

    return res.status(200).json({
      windowLive: win.live,
      remainingBlocks: win.remainingBlocks,
      remainingTxs: win.remainingTxs,
      opensAt,
      queued,
      queueEnabled: queueOn,
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};
