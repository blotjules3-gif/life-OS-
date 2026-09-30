// Serveur local pour essayer l'app sans deployer: node dev-server.mjs
// Sources fictives seulement (DEMO_PROVIDERS=yes), sauf si DUFFEL_TOKEN est
// fourni dans l'environnement du shell (cle de TEST Duffel, jamais de prod ici).
import http from "node:http";
import worker, { BudgetGate } from "./worker.js";

const store = new Map();
const STATE = {
  get: async (k) => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); }, delete: async (k) => { store.delete(k); },
  list: async ({ prefix }) => ({ keys: [...store.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })) }),
};
// Le vrai compteur de budget, en memoire.
const budgetStore = new Map();
const gate = new BudgetGate({ storage: { get: async (k) => budgetStore.get(k), put: async (k, v) => { budgetStore.set(k, v); } },
  blockConcurrencyWhile: (fn) => fn() });
const BUDGET = { idFromName: () => "global", get: () => ({ fetch: (url, init) => gate.fetch(new Request(url, init)) }) };
// ALERTS_CRON "on" ici pour essayer l'ecran des alertes; la verification planifiee
// ne tourne pas en local.
const env = { APP_KEY: process.env.APP_KEY || "dev-key", DEMO_PROVIDERS: "yes", STATE, BUDGET, ALERTS_CRON: "on",
  DUFFEL_TOKEN: process.env.DUFFEL_TOKEN || "", DAILY_BUDGET_USD: "1" };
const port = Number(process.env.PORT || 8787);

http.createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  const request = new Request(`http://127.0.0.1:${port}${req.url}`, { method: req.method, headers: req.headers,
    body: ["GET", "HEAD"].includes(req.method) ? undefined : body });
  const pending = [];
  const r = await worker.fetch(request, env, { waitUntil: (p) => pending.push(p) });
  res.writeHead(r.status, Object.fromEntries(r.headers));
  if (r.body) for await (const chunk of r.body) res.write(chunk);
  res.end();
  await Promise.all(pending);
  console.log(req.method, req.url, r.status);
}).listen(port, "127.0.0.1", () => console.log(`lifeos-flights local: http://127.0.0.1:${port}  (clé ${env.APP_KEY})`));
