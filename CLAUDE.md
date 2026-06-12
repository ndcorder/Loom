# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is a fork of the upstream project for development assistance. The original author did not scaffold consistently — expect three different product names baked into identifiers, two parallel Swift source trees, and an optional backend that the shipping app never actually calls. The sections below map what's real vs. aspirational so you don't trust a name or a file at face value.

## Naming history: AgentTrace → Loom → Tether

The project was renamed twice and the renames were never propagated cleanly. All three names are live in the code **right now**. This is the single biggest source of confusion — internalize it before touching anything:

| Layer | Where it appears |
| --- | --- |
| **Tether** | Brand/product. README, web UI, macOS app name + Xcode scheme, `Tether.app`, DMG name, `web/public/Tether.PNG`. |
| **Loom** | Rust binary `loom-proxy`; env vars `LOOM_ADDR`/`LOOM_DB`/`LOOM_CACHE`; cache file `loom-cache.sqlite`; runtime dir `~/Library/Caches/Loom/`; Xcode project `ui/Loom.xcodeproj`; SwiftPM package `LoomModules`; `LoomApp`. |
| **AgentTrace** | Oldest layer, survives in internals: JWT issuer/audience defaults (`"agenttrace"`, `"agenttrace-app"`); env var `AGENTTRACE_KEYS_SECRET`; UserDefaults keys `agenttrace.proxy.*`; session `trigger` string `"AgentTrace proxy"`; user-facing copy in DTO fallbacks. |

**Rule: match the name the surrounding layer already uses; never "unify" them.** Renaming a `LOOM_*` env var, a `loom-proxy` path, or an `agenttrace.proxy.port` UserDefaults key will silently break the launcher/persistence boundary because the two sides (Swift launcher ↔ Rust `std::env::var`, or Swift writer ↔ Swift reader) must agree on the exact string.

## The three components and how data flows

```
  LLM agent / Codex / Claude Code
        |  (points OPENAI_BASE_URL / ANTHROPIC_BASE_URL at the proxy)
        v
  proxy/  loom-proxy  (Rust, axum, 127.0.0.1:8080)
    |  - routes /v1/messages* -> Anthropic, everything else -> OpenAI
    |  - SQLite response cache (key = sha256(method+path+body))
    |  - records every call into trace_calls (SQLite)
    |  - serves /api/* JSON for the UI
    |  - (optional) Postgres-backed /api/auth + /api/settings  [NOT used by the app]
        ^
        |  HTTP poll every 1.2s  (GET /api/sessions, /api/traces/current)
  ui/   Tether.app  (SwiftUI, macOS 14+)
    |  - LocalProxyLauncher spawns loom-proxy as a child process
    |  - TraceStore merges TWO sources: proxy  +  ~/.codex SQLite logs
```

The components are only coupled at two seams: (1) the Swift `LocalProxyLauncher` spawns the Rust binary and feeds it env vars derived from `ProxySettingsStore`; (2) the packaging script bundles the Rust binary into the `.app`. The `web/` site is independent (marketing + waitlist) and shares no runtime code with the app.

---

## `proxy/` — Rust local proxy (`loom-proxy`)

Axum 0.8 / Tokio. Cargo edition **2024**. Entry point `src/main.rs`; the whole thing is one binary. The Axum router merges four sub-routers and a fallback:

```
auth::router()      -> /api/auth/*          (Postgres; 503 unless DATABASE_URL set)
settings::router()  -> /api/settings/*      (Postgres; 503 unless DATABASE_URL set)
trace::router()     -> /api/sessions, /api/traces/current, /api/cache   (SQLite)
proxy (fallback)    -> everything else: the actual LLM reverse proxy
```

### Request lifecycle (the `proxy` fallback handler in `main.rs`)

"cache → forward+tee → store":
1. Buffer the full request body (cap `MAX_BODY` = 100 MiB).
2. Pick upstream by path prefix: `/v1/messages*` → `anthropic_upstream` (Claude Code), else `openai_upstream` (Codex/OpenAI). The path+query is preserved verbatim onto the upstream base URL.
3. Build a `TraceCapture` from the request body (parses JSON to pull `model`, system/user prompts, a preview, `temperature`, request `id`).
4. **Cacheable = cache enabled AND method is POST.** Cache key = `sha256(method \n path_and_query \n body)`.
5. **Cache HIT** (cacheable + row exists): replay stored bytes with original status/content-type, add header `x-loom-cache: hit`, bump `hits`, record a trace row with `cache_status="hit"`, return — no network.
6. **MISS**: forward upstream with headers copied verbatim minus hop-by-hop + `host`/`content-length`. Then **tee** the response stream: each chunk is streamed to the client *and* accumulated. On clean completion of a 2xx, the accumulated body is written to the cache (if cacheable) and a trace row is recorded. If the client disconnects or the stream errors mid-flight, nothing is cached (partial responses are never stored) and an upstream-error trace row is written.

Streaming (SSE) responses are cached as the full accumulated body; on replay they come back as one buffered payload with the original `text/event-stream` content type. Non-cacheable / non-2xx paths still get traced but never cached. Trace capture for non-stored responses is bounded by `MAX_CAPTURE_BYTES` (256 KiB).

### Two separate datastores — do not conflate

- **SQLite (always on)** via `rusqlite`, single `Arc<Mutex<Connection>>`, WAL mode. Holds the response `cache` table (created inline in `main.rs`) and the trace tables (`sessions`, `trace_calls`). Trace schema lives in `proxy/sqlite_migrations/20260601000000_sessions.sql` but **there is no migration runner** — `trace::init_schema` applies it via `include_str!` and then hand-patches the table (adds `session_id` column if missing, backfills, ensures a current session). All SQLite work runs inside `tokio::task::spawn_blocking`.
- **Postgres (optional)** via `sqlx`, behind `AuthContext`. Holds `users` + `user_settings`. Schema in `proxy/migrations/` is applied by `sqlx::migrate!` at startup. This powers email/password auth (`argon2` hashes, `jsonwebtoken` HS256, 1h TTL), Google OAuth (PKCE + RS256 ID-token verification against Google JWKS), profile/settings CRUD, and AES-256-GCM-encrypted API-key storage (`src/crypto.rs`, format `v1:<nonce>:<ciphertext>`).

**Critical: the Postgres/auth half is dormant in normal use.** `AuthContext::from_env` returns `None` when `DATABASE_URL` is unset, and `LocalProxyLauncher` never sets it. So when the macOS app runs the proxy, every `/api/auth/*` and `/api/settings/*` route returns `503 "auth database is not configured"`. Treat the auth/settings code as a separate, not-yet-integrated backend, not part of the local app flow.

### Trace data model (`src/trace.rs`)

The proxy normalizes wildly different OpenAI/Anthropic request+response JSON shapes into one flat `trace_calls` row, then `/api/traces/current` reshapes rows into `AgentNodeDto`s (depth = ordinal index, `bar_percent` = latency normalized against the session max, status ∈ success|cached|error). `summarize_response`/`extract_response_text` handle `output_text`, `choices[].message.content`, Anthropic `content[].text`, and Responses-API `output[].content[].text`. Token counts come from `usage.{prompt,input}_tokens` / `usage.{completion,output}_tokens`. **`cost` is a hardcoded `"$0.0000"` stub everywhere** — there is no real cost calculation yet.

### HTTP API (what the UI consumes)

| Method + path | Purpose |
| --- | --- |
| `GET /api/sessions` | List sessions + current session id |
| `POST /api/sessions` | Create a new session (201) |
| `GET /api/traces/current?session_id=` | Snapshot: session + up to 500 nodes (defaults to current session) |
| `DELETE /api/traces/current` | Wipe `trace_calls` + `sessions`, recreate "Live Session" |
| `DELETE /api/cache` | Clear the response cache table only |
| `POST /api/auth/{register,login}`, `GET /api/auth/oauth/google[/callback]` | Postgres-gated; 503 without `DATABASE_URL` |
| `GET/POST /api/settings/*` | Postgres-gated; require `Authorization: Bearer <jwt>` |

### Proxy environment variables

| Var | Default | Effect |
| --- | --- | --- |
| `LOOM_ADDR` | `127.0.0.1:8080` | Listen address |
| `LOOM_DB` | `loom-cache.sqlite` | SQLite path (cache + traces) |
| `LOOM_CACHE` | on | `off`/`0`/`false` disables caching |
| `OPENAI_UPSTREAM` | `https://api.openai.com` | Non-`/v1/messages` upstream |
| `ANTHROPIC_UPSTREAM` | `https://api.anthropic.com` | `/v1/messages*` upstream |
| `DATABASE_URL` | unset | Postgres URL; **presence enables the entire auth/settings layer** |
| `JWT_SECRET` | — | Required (≥32 bytes) when `DATABASE_URL` set; panics otherwise |
| `JWT_ISSUER` / `JWT_AUDIENCE` | `agenttrace` / `agenttrace-app` | JWT claims |
| `GOOGLE_CLIENT_ID` / `_SECRET` / `_REDIRECT_URI` | unset | All three enable Google OAuth |
| `AGENTTRACE_KEYS_SECRET` | unset | Enables AES-GCM API-key encryption at rest |

---

## `ui/` — macOS SwiftUI app (Tether), macOS 14+, Swift 6

**Two parallel source trees — know which one you're in:**
- `ui/Loom/` — the **Xcode app target** (`Loom.xcodeproj`, scheme **Tether**, `@main LoomApp`). SwiftUI views under `Features/{Graph,Inspector,MainLayout,Settings,Sidebar,Welcome}`, plus `ContentView`, menu commands, window-chrome hiding. `TraceStore` (the app's main view-model) lives here at `Features/MainLayout/TraceStore.swift`.
- `ui/Sources/` — **SwiftPM modules** (`Package.swift`, package `LoomModules`): `Core` (models + TCA features), `UI` (design system, shared views), `Networking` (proxy launcher, API client, Codex observer), `App`. Depends on **The Composable Architecture (TCA)** 1.25.5. The Xcode target consumes these modules.

The split means a given concept (e.g. Sidebar, Inspector, SessionList) may exist in *both* trees. When editing UI, confirm whether the live screen is driven by `ui/Loom/Features/...` (the shipping app shell) or `ui/Sources/UI/...` (module views).

### `TraceStore`: dual trace sources with fallback priority

`TraceStore` polls every **1.2s** and merges two independent sources each refresh:
1. **Proxy** — `TraceAPIClient` hits `http://127.0.0.1:<port>/api/*` (2s request timeout, base URL from `ProxySettingsStore`).
2. **Codex observer** — `CodexLogObserver` reads Codex's own local SQLite directly.

Resolution order in `refresh()`: proxy snapshot with nodes → `.online`; else if no proxy sessions but Codex has nodes → `.observingCodex`; else fall back through proxy-empty / codex-empty / `.offline`. Net effect: the app shows *something* even with no proxy traffic, by surfacing Terminal Codex activity automatically.

### `LocalProxyLauncher`

Spawns `loom-proxy` as a child `Process`, looking in two places (first executable wins):
1. `proxy/target/debug/loom-proxy` (dev — resolved relative to `#filePath`'s repo root)
2. `Tether.app/Contents/Helpers/loom-proxy` (packaged)

Runtime dir is `~/Library/Caches/Loom/` (holds `loom-cache.sqlite` and `proxy.log`). It injects `LOOM_ADDR`, `LOOM_CACHE`, `OPENAI_UPSTREAM`, `ANTHROPIC_UPSTREAM`, `LOOM_DB` from `ProxySettingsStore.current` — and notably **not** `DATABASE_URL` (confirming auth is out of the app path). `ProxySettingsStore` persists to `UserDefaults` under `agenttrace.proxy.*` keys.

### `CodexLogObserver` — brittle external dependency

Reads two hardcoded, version-numbered files in `~/.codex/`: `state_5.sqlite` (threads) and `logs_2.sqlite` (logs), by shelling out to `/usr/bin/sqlite3 -readonly -json` and parsing websocket `response.*` events out of `feedback_log_body`. **These filenames and the log/JSON shape are owned by the Codex CLI, not this repo** — a Codex update that bumps `state_5`/`logs_2` or changes the log format will silently break this observer (it degrades to returning `nil`, not an error). If the Codex panel goes blank, check these paths first.

---

## `web/` — Next.js 15 marketing site

Next.js 15 App Router / React 19 / TypeScript (strict). Independent of the app/proxy.
- `app/page.tsx` (~47 KB) — the landing page; `app/globals.css` (~47 KB) holds the design-token system (dark/light themes). `app/layout.tsx` has the metadata/SEO.
- `app/[slug]/page.tsx` — dynamic info pages (features/docs/pricing/etc.) driven by `lib/site-pages.ts` + `lib/data.ts`.
- `app/api/waitlist/route.ts` and `app/api/feedback/route.ts` — both send email via **Resend** (needs `RESEND_API_KEY`). Submissions are also appended to `web/data/*.ndjson` (gitignored).
- `components/` mirrors the app's UI (`GraphCanvas`, `Inspector`, `Sidebar`) as a static landing-page demo — these are *not* the real app, just a marketing recreation.
- `public/downloads/` is where `package-dmg.sh` drops the built `Tether.dmg`.

---

## Commands

Run each component from its own directory.

**Web** (`cd web`, npm — `package-lock.json`):
```bash
npm install
npm run dev        # http://localhost:3000
npm run build && npm start
npm run lint       # next lint
```

**Proxy** (`cd proxy`, Cargo edition 2024):
```bash
cargo build [--release]
cargo test                       # (no unit tests exist yet; this just compiles+passes)
LOOM_ADDR=127.0.0.1:8080 LOOM_CACHE=on cargo run   # all env vars optional; see table above
```
Then point a client: `OPENAI_BASE_URL=http://127.0.0.1:8080/v1` or `ANTHROPIC_BASE_URL=http://127.0.0.1:8080`.

**UI** (macOS only):
```bash
swift build --package-path ui                                   # build the SwiftPM modules
xcodebuild -project ui/Loom.xcodeproj -scheme Tether -configuration Release build
```

**End-to-end smoke test** (the closest thing to an integration test: starts a Node mock upstream + the real proxy, sends requests through, asserts on the SQLite + responses; needs `cargo`, `node`, `sqlite3`, `curl`):
```bash
npm run smoke:e2e --prefix web    # or: scripts/smoke-e2e.sh
```

**Package the DMG** (builds the Rust proxy + Xcode app, bundles the helper into `Tether.app/Contents/Helpers/`, ad-hoc signs, makes the DMG, copies it to `web/public/downloads/`):
```bash
npm run package:dmg --prefix web  # or: scripts/package-dmg.sh
```

---

## Known gaps & scaffolding issues (this fork's working notes)

- **Cost is a stub.** Every trace row and node reports `$0.0000`; there's no token-pricing logic anywhere. The README markets "cost visibility" — it isn't implemented.
- **No migration runner for the local SQLite.** Trace-schema changes must go in `proxy/sqlite_migrations/` AND be reflected in `trace::init_schema`'s hand-patching (column adds / backfill), or existing dev DBs at `~/Library/Caches/Loom/loom-cache.sqlite` won't pick them up.
- **Auth/settings layer is unintegrated.** Fully implemented against Postgres but never invoked by the app. Decide explicitly whether to wire it in or treat it as dead code before building on it.
- **Codex observer depends on private Codex CLI internals** (`~/.codex/state_5.sqlite`, `logs_2.sqlite`, websocket-event log format). Expect breakage on Codex updates.
- **Three-name inconsistency** (above) is repo-wide and load-bearing in env vars / UserDefaults keys / JWT defaults. Don't "clean it up" without tracing both sides of each string.
- **Only `scripts/smoke-e2e.sh` exercises real behavior.** No Rust unit tests, no JS tests, no Swift tests. When changing proxy routing/caching/trace logic, extend the smoke test — it's the safety net.

## Editing conventions

- Match the naming layer of the file you're in (Tether brand strings, `loom`/`LOOM_*` identifiers, `agenttrace.*` persistence keys). The smoke test will catch a mismatched env-var rename; nothing will catch a mismatched UserDefaults key.
- SQLite access in the proxy is synchronous `rusqlite` wrapped in `spawn_blocking` over a shared `Mutex<Connection>` — keep that pattern; don't introduce a second connection or block the async runtime.
- The proxy forwards headers verbatim minus hop-by-hop + `host`/`content-length`; preserve that when touching request/response plumbing or you'll corrupt streaming or auth headers.
