// Reqo AI (Vercel function). Groq free tier, key on the server only.
// The model replies in text and ends with at most one JSON action. It never signs or sends anything.
// Every action is validated here before the app sees it.

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const MODEL = process.env.GROQ_MODEL || "openai/gpt-oss-120b";
const MAX_TURNS = 12;
const MAX_CHARS = 1000;
const MAX_PER_HOUR = 30;
const hits = new Map();

const SYSTEM = `You are Reqo AI, the assistant inside Reqo, a memecoin launchpad on QoreChain testnet.
You help users create a memecoin and buy or sell Reqo tokens. You never sign or send anything. The app always asks the user to confirm.

A launch needs four fields:
- name: 1 to 32 characters
- ticker: 1 to 10 letters or digits, no $ sign
- supply: a whole number from 1 to 1000000000000
- description: up to 200 characters, fun and short

An image is optional. You cannot see images and you cannot create pictures. Never offer to draw, generate or find an image. The user uploads their own picture. If the user says an image is attached, say it will be used as the token image.

Rules:
- If the user asks for a meme idea, even from one short prompt, invent a complete original coin with all four fields. Do not ask questions first.
- If the user gives some details, keep them and fill the rest with sensible choices.
- Ask a question only when the request has nothing usable.
- For a buy or sell, you need the side (buy or sell), the token (a ticker such as CROAK or $CROAK, or a 0x contract address), and the amount. If any is missing, ask for it. Never guess a token.

Output format:
1. One short, friendly sentence.
2. If you produced a coin or a trade, then one JSON object on its own line and nothing after it:
   Launch: {"action":"draft","name":"...","symbol":"...","supply":"...","description":"..."}
   Trade:  {"action":"trade","side":"buy","token":"...","amount":"..."}
If you are only asking a question, output no JSON.`;

function rateOk(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 3600000);
  if (list.length >= MAX_PER_HOUR) { hits.set(ip, list); return false; }
  list.push(now); hits.set(ip, list); return true;
}

// Takes the last JSON object that carries an action; ignores anything else in the reply.
function extractAction(text) {
  const matches = text.match(/\{[^{}]*"action"[^{}]*\}/g);
  if (!matches) return null;
  for (let i = matches.length - 1; i >= 0; i--) {
    try { return JSON.parse(matches[i]); } catch (e) {}
  }
  return null;
}

function validateDraft(d) {
  const enc = new TextEncoder();
  const errs = [];
  const name = String(d.name || "").trim();
  const symbol = String(d.symbol || "").trim().replace(/^\$/, "");
  const supplyStr = String(d.supply || "").replace(/[, ]/g, "").trim();
  const description = String(d.description || "").trim();
  if (!name || enc.encode(name).length > 32) errs.push("name must be 1 to 32 bytes");
  if (!/^[A-Za-z0-9]{1,10}$/.test(symbol)) errs.push("ticker must be 1 to 10 letters or digits");
  if (!/^\d+$/.test(supplyStr) || BigInt(supplyStr) < 1n || BigInt(supplyStr) > 1000000000000n) errs.push("supply must be a whole number from 1 to 1000000000000");
  if (enc.encode(description).length > 280) errs.push("description is too long");
  if (errs.length) return { ok: false, errors: errs };
  return { ok: true, draft: { name, symbol: symbol.toUpperCase(), supply: supplyStr, description } };
}

function validateTrade(t) {
  const side = String(t.side || "").toLowerCase();
  const token = String(t.token || "").trim();
  const amount = String(t.amount || "").trim();
  const errs = [];
  if (side !== "buy" && side !== "sell") errs.push("side must be buy or sell");
  if (!(/^0x[0-9a-fA-F]{40}$/.test(token) || /^\$?[A-Za-z0-9]{1,10}$/.test(token))) errs.push("token must be a ticker or a 0x address");
  if (!/^\d+(\.\d+)?$/.test(amount) || Number(amount) <= 0) errs.push("amount must be a number above zero");
  if (errs.length) return { ok: false, errors: errs };
  return { ok: true, trade: { side, token: token.replace(/^\$/, ""), amount } };
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
    if (body.imageAttached && history.length) {
      const last = history[history.length - 1];
      last.content += "\n[The user attached an image. It will be the token image.]";
    }

    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: { Authorization: "Bearer " + process.env.GROQ_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.7,
        max_tokens: 500,
        messages: [{ role: "system", content: SYSTEM }, ...history],
      }),
    });
    if (!r.ok) {
      const detail = (await r.text()).replace(/gsk_[A-Za-z0-9]+/g, "[key]").slice(0, 300);
      return res.status(502).json({ error: "agent is unavailable right now (HTTP " + r.status + ")", model: MODEL, detail });
    }
    const j = await r.json();
    const text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
    const action = extractAction(text);
    const reply = text.replace(/\{[^{}]*"action"[^{}]*\}/g, "").trim();

    if (action && action.action === "draft") {
      const v = validateDraft(action);
      if (!v.ok) return res.status(200).json({ reply: "I need a fix before this coin can be created: " + v.errors.join("; ") + ".", draft: null, trade: null });
      return res.status(200).json({ reply, draft: v.draft, trade: null });
    }
    if (action && action.action === "trade") {
      const v = validateTrade(action);
      if (!v.ok) return res.status(200).json({ reply: "I need a fix before this trade: " + v.errors.join("; ") + ".", draft: null, trade: null });
      return res.status(200).json({ reply, draft: null, trade: v.trade });
    }
    return res.status(200).json({ reply, draft: null, trade: null });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
};
