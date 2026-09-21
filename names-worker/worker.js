// Noms des outils LifeOS, lus dans la table Notion.
//
// Theo renomme un outil dans Notion, l'app lit ce point a l'ouverture, et le
// nouveau nom apparait sans nouvelle version de l'app.
//
// La cle Notion reste ICI, jamais dans l'app: une cle embarquee dans un
// binaire iOS se lit en deux minutes.
//
// Ce point ne casse jamais l'app. Sans cle, avec Notion en panne, ou avec une
// table abimee, il rend les derniers noms connus, puis les noms d'origine.

import { FALLBACK } from "./fallback.js";

const NOTION = "https://api.notion.com/v1";
const VERSION = "2022-06-28";
const CACHE_SECONDS = 300;   // 5 min: assez frais, et Notion limite a ~3 appels/s
const MAX_LEN = 40;

// Colonnes attendues, par leur titre, pas par leur position: deplacer une
// colonne dans Notion ne doit rien casser.
const COL_NEW = "nouveau nom lifeos";
const COL_OLD = "nom descriptif";

export function clean(s) {
  return String(s ?? "").replace(/\s+/g, " ").trim();
}

/** Lit les lignes de toutes les tables. Pur, donc testable sans reseau. */
export function namesFromRows(tables) {
  const out = {};
  const problems = [];
  for (const rows of tables) {
    if (!rows.length) continue;
    const head = rows[0].map((c) => clean(c).toLowerCase());
    const iNew = head.indexOf(COL_NEW);
    const iOld = head.indexOf(COL_OLD);
    if (iNew < 0 || iOld < 0) continue;          // pas une table d'outils
    for (const r of rows.slice(1)) {
      const oldName = clean(r[iOld]);
      const newName = clean(r[iNew]);
      if (!(oldName in FALLBACK)) continue;      // outil inconnu de l'app: ignore
      if (!newName) { problems.push(`${oldName}: nom vide`); continue; }
      if (newName.length > MAX_LEN) { problems.push(`${oldName}: plus de ${MAX_LEN} caracteres`); continue; }
      out[oldName] = newName;
    }
  }
  return { names: out, problems };
}

async function notion(path, token) {
  const r = await fetch(NOTION + path, {
    headers: { Authorization: `Bearer ${token}`, "Notion-Version": VERSION },
  });
  if (!r.ok) throw new Error(`Notion ${r.status} sur ${path}`);
  return r.json();
}

async function children(id, token) {
  const all = [];
  let cursor;
  do {
    const q = `/blocks/${id}/children?page_size=100` + (cursor ? `&start_cursor=${cursor}` : "");
    const page = await notion(q, token);
    all.push(...page.results);
    cursor = page.has_more ? page.next_cursor : undefined;
  } while (cursor);
  return all;
}

const cellText = (cell) => (cell || []).map((t) => t.plain_text).join("");

async function readNotion(env) {
  const blocks = await children(env.NOTION_PAGE_ID, env.NOTION_TOKEN);
  const tables = [];
  for (const b of blocks) {
    if (b.type !== "table") continue;
    const rows = await children(b.id, env.NOTION_TOKEN);
    tables.push(rows.filter((r) => r.type === "table_row").map((r) => r.table_row.cells.map(cellText)));
  }
  return namesFromRows(tables);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${CACHE_SECONDS}`,
    },
  });
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (url.pathname !== "/names") return new Response("Not found.", { status: 404 });

    const cache = caches.default;
    const key = new Request(url.origin + "/names");
    const hit = await cache.match(key);
    if (hit) return hit;

    // Base: les noms d'origine, recouverts par ce que Notion dit.
    let names = { ...FALLBACK };
    let source = "fallback";
    let problems = [];
    if (env.NOTION_TOKEN && env.NOTION_PAGE_ID) {
      try {
        const r = await readNotion(env);
        if (Object.keys(r.names).length) {
          names = { ...names, ...r.names };
          source = "notion";
          problems = r.problems;
          ctx.waitUntil(env.NAMES.put("last", JSON.stringify(names)));
        }
      } catch (e) {
        // Notion en panne: les derniers noms lus valent mieux que les anciens.
        const last = await env.NAMES.get("last");
        if (last) { names = JSON.parse(last); source = "last-known"; }
        problems = [String(e.message || e)];
      }
    }

    const res = json({ source, updatedAt: new Date().toISOString(), names, problems });
    ctx.waitUntil(cache.put(key, res.clone()));
    return res;
  },
};
