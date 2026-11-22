// Reqo launch agent (Vercel function). Uses Groq's free tier, server side only.
// The model collects token details and returns JSON. It never builds or signs transactions.
// Every field it returns is validated here before the page shows it.

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const MODEL = process.env.GROQ_MODEL || "llama-3.3-70b-versatile"; // set GROQ_MODEL in Vercel to any model ID from console.groq.com
const MAX_TURNS = 12;
const MAX_CHARS = 1000;
const MAX_PER_HOUR = 30;
const hits = new Map();

const SYSTEM = `You help a user create a memecoin on QoreChain testnet.
You collect four details: name (1 to 32 characters), ticker (1 to 10 letters or digits), total supply (whole number from 1 to 1000000000000), and a short description (up to 280 characters).
Ask for one missing detail at a time. Keep replies short and friendly. Never claim you can sign, send, or deploy anything. The user reviews and signs the transaction themselves.
When all four details are known and the user has confirmed them, reply with a short sentence followed by a single JSON object on its own line, and nothing else in the JSON:
{"ready":true,"name":"...","symbol":"...","supply":"...","description":"..."}
Until then, do not output any JSON.`;

function rateOk(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 3600000);
  if (list.length >= MAX_PER_HOUR) { hits.set(ip, list); return false; }
  list.push(now); hits.set(ip, list); return true;
}

function extractDraft(text) {
  const m = text.match(/\{[^{}]*"ready"\s*:\s*true[^{}]*\}/);
  if (!m) return null;
  try { return JSON.parse(m[0]); } catch (e) { return null; }
}

function validate(d) {
  const enc = new TextEncoder();
  const errs = [];
  const name = String(d.name || "").trim();
  const symbol = String(d.symbol || "").trim();
  const supplyStr = String(d.supply || "").trim();
  const description = String(d.description || "").trim();
  if (!name || enc.encode(name).length > 32) errs.push("name must be 1 to 32 bytes");
  if (!/^[A-Za-z0-9]{1,10}$/.test(symbol)) errs.push("ticker must be 1 to 10 letters or digits");
  if (!/^\d+$/.test(supplyStr) || BigInt(supplyStr) < 1n || BigInt(supplyStr) > 1000000000000n) errs.push("supply must be a whole number from 1 to 1000000000000");
  if (enc.encode(description).length > 280) errs.push("description must be 280 bytes or less");
  if (errs.length) return { ok: false, errors: errs };
  return { ok: true, draft: { name, symbol: symbol.toUpperCase(), supply: supplyStr, description } };
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  if (!process.env.GROQ_API_KEY) return res.status(503).json({ error: "agent is not configured" });

  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
  if (!rateOk(ip)) return res.status(429).json({ error: "too many messages from this network, try again later" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const history = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
      .slice(-MAX_TURNS)
      .map((m) => ({ role: m.role, content: m.content.slice(0, MAX_CHARS) }));
    if (!history.length || history[history.length - 1].role !== "user") throw new Error("send a message");

    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: { Authorization: "Bearer " + process.env.GROQ_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.2,
        max_tokens: 400,
        messages: [{ role: "system", content: SYSTEM }, ...history],
      }),
    });
    if (!r.ok) {
      const detail = (await r.text()).replace(/gsk_[A-Za-z0-9]+/g, "[key]").slice(0, 300);
      return res.status(502).json({ error: "agent is unavailable right now (HTTP " + r.status + ")", model: MODEL, detail });
    }
    const j = await r.json();
    const text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";

    const raw = extractDraft(text);
    const reply = text.replace(/\{[^{}]*"ready"[^{}]*\}/g, "").trim();
    if (!raw) return res.status(200).json({ reply, draft: null });

    const v = validate(raw);
    if (!v.ok) return res.status(200).json({ reply: "Some details need changing: " + v.errors.join("; ") + ".", draft: null });
    return res.status(200).json({ reply, draft: v.draft });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
};
