import express from "express";
import fetch from "node-fetch";
import cors from "cors";
import morgan from "morgan";
import helmet from "helmet";
import compression from "compression";
import dotenv from "dotenv";

dotenv.config();

const {
  PORT = 3000,
  BC_STORE_HASH,
  BC_ACCESS_TOKEN,
  BC_API_BASE = "https://api.bigcommerce.com",
} = process.env;

if (!BC_STORE_HASH || !BC_ACCESS_TOKEN) {
  console.error("❌ Missing BC_STORE_HASH or BC_ACCESS_TOKEN in .env");
  process.exit(1);
}

const app = express();

// Basic hardening + CORS (adjust origin to your app domain in prod)
app.use(helmet());
app.use(cors({ origin: true })); // set to your domain for production
app.use(compression());
app.use(morgan("tiny"));

/**
 * Whitelist allowed query params you want to proxy through.
 * Add more as needed (e.g., "id:in", "sku", etc.).
 */
const ALLOWED_PARAMS = new Set([
  "name:like",
  "categories:in",
  "limit",
  "page",
  "include",
  "is_visible",
  "availability",
  "sort",
  "direction"
]);

function buildQueryString(reqQuery) {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(reqQuery)) {
    if (ALLOWED_PARAMS.has(k)) {
      // Allow repeated values like id:in=1,2,3 or categories:in=123
      qs.append(k, String(v));
    }
  }
  return qs.toString();
}

async function proxyToBC(path, req, res) {
  const qs = buildQueryString(req.query);
  const url = `${BC_API_BASE}/stores/${BC_STORE_HASH}/v3${path}${qs ? `?${qs}` : ""}`;
  try {
    const bcResp = await fetch(url, {
      headers: {
        "X-Auth-Token": BC_ACCESS_TOKEN,
        "Accept": "application/json",
      },
    });

    const text = await bcResp.text(); // pass body through as-is
    res.status(bcResp.status);
    // Forward BigCommerce rate limit headers for observability
    ["X-Rate-Limit-Requests-Left", "X-Rate-Limit-Time-Reset-Ms"].forEach(h => {
      const v = bcResp.headers.get(h);
      if (v) res.setHeader(h, v);
    });
    res.type("application/json").send(text);
  } catch (err) {
    console.error("BC proxy error:", err);
    res.status(502).json({ status: 502, error: "Bad Gateway", detail: "Upstream request to BigCommerce failed." });
  }
}

// ---- Routes your Flutter app uses ----

// Product search / listing (supports name:like, categories:in, limit, page, etc.)
app.get("/api/catalog/products", async (req, res) =>
  proxyToBC("/catalog/products", req, res)
);

// (Optional) Categories if you need them later
app.get("/api/catalog/categories", async (req, res) =>
  proxyToBC("/catalog/categories", req, res)
);

// Health check
app.get("/api/health", (req, res) => res.json({ ok: true }));

app.listen(Number(PORT), () => {
  console.log(`✅ HMSC BigCommerce proxy running on http://localhost:${PORT}`);
});
