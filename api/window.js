// Reqo window status proxy (Vercel function). The browser cannot call the QoreChain REST API
// directly, so this function fetches the window status server side and returns it as JSON.
// It stores nothing and holds no keys.

const API = "https://api-testnet.qore.host";
const QOR_RE = /^qor1[02-9ac-hj-np-z]{38,}$/;

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "GET") return res.status(405).json({ error: "GET only" });
  const qor = String((req.query && req.query.qor) || "");
  if (!QOR_RE.test(qor)) return res.status(400).json({ error: "qor parameter must be a qor1 address" });
  try {
    const r = await fetch(API + "/qorechain/pqc/v1/evm_window/" + qor);
    const text = await r.text();
    if (!r.ok) return res.status(502).json({ error: "chain window service returned HTTP " + r.status, body: text.slice(0, 200) });
    let j;
    try { j = JSON.parse(text); } catch (e) { return res.status(502).json({ error: "chain window service returned non-JSON" }); }
    return res.status(200).json({ qor, live: !!j.live, remaining_blocks: j.remaining_blocks ?? null, remaining_txs: j.remaining_txs ?? null, expiry_height: j.expiry_height ?? null, max_txs: j.max_txs ?? null, max_value: j.max_value ?? null });
  } catch (e) {
    return res.status(502).json({ error: "could not reach the chain window service: " + e.message });
  }
};
