# lifeos-flights: the LifeOS flight comparator engine

LifeOS has its own engine. Skyscanner is only a model for what the product should do. No Skyscanner API, no reseller of its results, no iframe, no redirect.

- The app (tool **Envol** in Voyage, `LifeOS/Modules/FlightCompare.swift`) talks **only to this Worker**.
- The Worker holds the provider keys (Cloudflare secrets). It searches several sources, puts the results into one shared format, groups them and ranks them.
- **Status on 2026-09-28: built and tested locally. Not deployed. No real source is connected.**

## Files

| File | Role |
|---|---|
| `core.js` | Shared format, request checks, time zones, analysis (stops, self transfer, airport change, overnight stay), grouping without merging, ranking, filters, comparability |
| `engine.js` | Parallel search, one time limit per source, cancel, partial results, one batch per source as it arrives, dated cache (10 min), budget, costs, price check before handoff, alerts |
| `providers/duffel.js` | Real Duffel adapter (API v2), ready. Active once `DUFFEL_TOKEN` is set |
| `providers/travelport.js` | **Skeleton only**: no OAuth, no search, no mapping written. A secret does not turn it on. The connector must be written, then certified |
| `providers/demo.js` | Two fictional sources (`demo-a`, `demo-b`), only when `DEMO_PROVIDERS=yes`, always labelled "fictif" (fictional) |
| `worker.js` | HTTP routes, app key, atomic budget (`BudgetGate` Durable Object), limit per IP address, ECB exchange rates, streaming, KV alerts, cron |
| `dev-server.mjs` | Local server for testing the app without deploying |
| `test-flights.mjs` | 40 checks, no network |

## Routes

All routes except `/v1/health` need the `X-LifeOS-Key` header.

- `GET /v1/providers`: list of sources and what each one can do. `multiSource` is true only with **2 real sources active** (demo sources never count).
- `POST /v1/search`: `{slices:[{origin,destination,date}], passengers, cabin, currency, maxConnections, filters}`. `?stream=1` sends one NDJSON line per source, then the result.
- `POST /v1/confirm`: `{offer, query}`. Checks the offer again **with its own source** and answers `same_price`, `price_changed` (with the difference) or `unavailable`. One source's IDs are never sent to another source.
- `POST /v1/alerts`, `GET|DELETE /v1/alerts/:id?token=`: price alerts, checked by the cron, with unsubscribe.

## Rules fixed after the audit of 28 Sept 2026

- **Budget, before any paid call.** `BudgetGate` is a Durable Object: a small Cloudflare
  server object that handles one request at a time. It checks and reserves the cost with no
  wait in between, so two searches cannot spend the same amount. It then settles the real
  cost. Without this binding, Duffel is **never** called and the result says why.
  Proven: budget for one call, three searches at once, **one** Duffel call.
- **Limit per person:** 40 paid searches per IP address per day (`CLIENT_DAILY_SEARCHES`).
  The app key is shared with the app, so it is **not** an identity. Real limits per user
  need real accounts.
- **One currency per ranking.** An offer in another currency is compared only after
  conversion at the ECB (European Central Bank) rate of a known date. The billed price stays
  visible (`price.original`). With no rate, the offer is **set aside**, never ranked.
  `rank()` refuses mixed currencies. Alerts only fire on a price billed in the alert's
  currency.
- **Filters apply to each offer.** A flight stays only if **one** offer passes **all** the
  filters. Then the price shown, the analysis and the explanation are recalculated. The app
  sends its filters to the server instead of filtering on its side.
- **Children:** the age of each child is required and sent to Duffel. There is no default
  age. Baggage is read **per traveller**: the number shown is the one guaranteed to all,
  and `varies` says when it differs.
- **Dates:** `2027-02-31` is refused. **Price check:** 15 s time limit, and the offer must
  be the same itinerary. A change of currency is reported, not turned into a difference.
- **Cache:** at most 200 searches, old entries removed. Identical searches running at the
  same time share one call. It is **per Worker instance**, not global.
- **Progressive results:** each batch sent on the stream is a full partial result (offers,
  ranking). The app shows it as soon as it arrives.
- **Alerts:** switched off until the cron runs **and** `ALERTS_CRON = "on"`. Until then the
  server refuses to create one, and the app says so. The cron reads every page, one broken
  alert does not stop the others, and an alert deleted during the run is not recreated. The
  server does the check; **the app** shows a drop once, when Envol is opened (local
  notification). There is no push notification yet (it needs an APNs key, Apple's push
  service).

## Source and capability matrix (checked on 2026-09-28)

| Source | Type | Access today | Airlines | Seller comparison | Bags / conditions | Price check | Handoff to seller | Cost |
|---|---|---|---|---|---|---|---|---|
| **Duffel** | Technical distributor (NDC, GDS, some low cost) | **Self-serve**: account + test key, free | Depends on the airline, measured by the matrix once connected | **No**: a single technical seller (Duffel) | Per segment and passenger / before departure | Yes (`GET /air/offers/{id}`) | **No link to the airline.** Only booking through Duffel, which makes LifeOS the seller | $0.005 per search over 1,500 per order; $3 + 1% per order |
| **Travelport** | GDS + NDC | **Contract** + OAuth credentials + certification | Wide (GDS), NDC per airline | No | Per fare | Yes | Booking API | Contract terms |
| Amadeus Self-Service | GDS | **Closed on 17 July 2026** | — | — | — | — | — | — |
| Kiwi Tequila | Low-cost OTA | **By invitation only** | — | — | — | — | — | — |
| `demo-a`, `demo-b` | Fictional | Local only | "Démo Air" | — | Fictional | Fictional | None | 0 |

**What this means, plainly:**
- With Duffel alone, LifeOS shows **several airlines through one distributor**. That is **not** a comparison of several agencies. The screen shows sources and sellers, not "the whole market".
- **No second real source can be reached today without a contract.** So the product is **not** a working multi-source comparator. The engine is built for it, and it is proven with fictional sources and simulated failures.
- No scraping and no invented prices fill the gaps.

## Tested journeys

`node test-flights.mjs` (40/40), including every audit case above, plus: request and error checks, time zones across the clock change (25 Oct 2026), Duffel mapping from the documented format (unknown bags stay "unknown", never 0), exact Duffel request (headers, body), expired offer shown as unavailable, Duffel without a key never called, Travelport never active, same itinerary at 2 sources grouped with its offers kept separate, one source down gives partial results, slow source cut off, batches in arrival order, one source cannot inject another source's offers, dated cache (no cache when results are partial), budget cap, check with same / new price / unavailable, cheapest ranking that does not favour unknown fees, "best" with a plain explanation, airport change and overnight stay, filters, alerts (fire once, re-arm, never on demo or incomplete prices), 401, end-to-end Duffel search with cost counted, cache that costs nothing, alerts with token and unsubscribe, cron fires the alert, progressive stream.

Checked by hand in the app (iPhone 17 Pro Max simulator, local server, fictional sources): form, return search, sources strip, demo banner, the same flight at 2 sources on one card (4 offers), plain-words explanation, alert refused on fictional prices, offer detail with differences explained, price confirmed, added to a new trip marked "non réservé" (not booked).

## Forecast costs

- Duffel: without any order, **every search is extra, at $0.005**. 1,000 searches per day = $5/day. The **daily cap** (`DAILY_BUDGET_USD`, default $5) is enforced atomically by `BudgetGate`: once it is reached, Duffel is skipped and the result says so.
- Durable Objects need the Workers paid plan ($5/month) unless the SQLite-backed free tier applies to this account. Check before deploying.
- The 10-minute cache per Worker instance means a repeated search costs nothing.
- Alerts: one search per alert per cron run. At 4 runs per day, 100 alerts = 400 searches = $2/day. It stays under the same cap.
- Cloudflare: Workers and KV on the free plan are enough at the start. **But the account's 5 free crons are already taken** (see workspace CLAUDE.md), so the alert cron needs a slot freed or the paid plan.

## Configuration

Worker (`wrangler.toml`, nothing deployed):
```
npx wrangler kv namespace create STATE
npx wrangler secret put APP_KEY
npx wrangler secret put DUFFEL_TOKEN      # duffel_test_... first
```
App (`Config.xcconfig`): `FLIGHTS_API_URL` (https only) and `FLIGHTS_APP_KEY`. When they are empty, the screen says "pas encore branché" (not connected yet) and sends no search.
Local test: `node dev-server.mjs`, then run the app in DEBUG with `-flightsAPI http://127.0.0.1:8787 -shotTool Envol -flightsQuery LIS-CDG-30`.

## Commercial steps left, and who can do them

1. **Duffel**: create the account and a **test** key. Only Theo can do this (account creation). Then measure real coverage with the matrix (airlines, low cost, markets) before any live key.
2. **Seller handoff**: Duffel has no link to the airline. Options to check with Duffel: its hosted booking page (Duffel Links) or its merchant model. Direct booking would make LifeOS the seller (payment, ticketing, cancellation, customer service): **not turned on**, it needs its own decision.
3. **Second real source**: a contract with Travelport (or an agency with its access), or direct deals with airlines / NDC. Nothing is signed or bought automatically.
4. **Push alerts**: today the app reads alert status when you open "Favoris et alertes" (favourites and alerts). Push needs an APNs key and a send route.
5. **Nearby airports / city search**: needs a places API (Duffel has `/places/suggestions`), to connect once the key exists. Today you type the 3-letter code.
6. **Price calendar and budget exploration**: none of the sources has an honest flexible calendar. Not built, not faked.
