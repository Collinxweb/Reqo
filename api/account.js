// Reqo account status proxy (Vercel function). The browser cannot call api-testnet.qore.host directly
// (it sends no CORS headers), so this returns the account's registration status server side.
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
    const r = await fetch(API + "/qorechain/pqc/v1/account/" + qor);
    const text = await r.text();
    if (!r.ok) return res.status(502).json({ error: "chain account service returned HTTP " + r.status });
    let j;
    try { j = JSON.parse(text); } catch (e) { return res.status(502).json({ error: "chain account service returned non-JSON" }); }
    const acc = j.account || null;
    return res.status(200).json({
      qor,
      found: !!j.found,
      key_type: acc ? acc.key_type || null : null,
      algorithm_name: acc ? acc.algorithm_name || null : null,
      possession_proven: acc ? !!acc.possession_proven : false,
      created_at_height: acc ? acc.created_at_height || null : null,
    });
  } catch (e) {
    return res.status(502).json({ error: "could not reach the chain account service: " + e.message });
  }
};
