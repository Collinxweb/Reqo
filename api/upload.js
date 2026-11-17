// Reqo v2.2.0 image upload. Accepts a base64 image, checks its real file type,
// stores it in Vercel Blob, and returns the public URL.
// Requires BLOB_READ_WRITE_TOKEN (created when a Blob store is connected to the project).

const crypto = require("crypto");

const MAX_BYTES = 1024 * 1024; // 1 MB
const TYPES = {
  "image/png": { ext: "png", check: (b) => b.slice(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])) },
  "image/jpeg": { ext: "jpg", check: (b) => b.slice(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff])) },
  "image/webp": {
    ext: "webp",
    check: (b) => b.slice(0, 4).toString("ascii") === "RIFF" && b.slice(8, 12).toString("ascii") === "WEBP",
  },
};

const hits = new Map();
function rateOk(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 3600000);
  if (list.length >= 10) {
    hits.set(ip, list);
    return false;
  }
  list.push(now);
  hits.set(ip, list);
  return true;
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return res.status(503).json({ error: "image storage not configured" });

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const type = TYPES[body.contentType];
    if (!type) throw new Error("unsupported image type (use PNG, JPEG or WebP)");
    if (typeof body.data !== "string") throw new Error("missing image data");

    const buf = Buffer.from(body.data, "base64");
    if (buf.length === 0 || buf.length > MAX_BYTES) throw new Error("image must be under 1 MB");
    if (!type.check(buf)) throw new Error("file content does not match its type");

    const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
    if (!rateOk(ip)) return res.status(429).json({ error: "upload limit reached: 10 per hour" });

    const pathname = `token-images/${crypto.randomBytes(12).toString("hex")}.${type.ext}`;
    const up = await fetch(`https://blob.vercel-storage.com/${pathname}`, {
      method: "PUT",
      headers: {
        authorization: `Bearer ${token}`,
        "x-api-version": "7",
        "x-content-type": body.contentType,
        "x-add-random-suffix": "0",
        "content-type": body.contentType,
      },
      body: buf,
    });
    const j = await up.json();
    if (!up.ok || !j.url) throw new Error((j.error && j.error.message) || "upload failed");

    return res.status(200).json({ url: j.url });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
};
