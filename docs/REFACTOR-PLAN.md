# Tether (Loom) — Refactor Plan

_Working notes for cleaning up the fork. Author of this doc: development assistance pass, 2026-06-12._

## 0. License (do this first — it gates everything else)

No `LICENSE` file, no `license` field in `Cargo.toml`/`package.json`. Default copyright = all rights reserved. Forking/learning is fine under GitHub TOS; relicensing or shipping a product is not, until the author adds a license.

**Recommendation: ask the author to add MIT** (or Apache-2.0). A permissive license is in *our* interest — it maximizes what we can legally do with the fork. MIT = simplest. Apache-2.0 = same permissions + an explicit patent grant and NOTICE requirement (marginally safer given the auth/crypto code). Either is fine; MIT is the conventional default for a small dev tool. All current deps (Rust crates, swift-composable-architecture, Next.js stack) are permissive and compatible with shipping under MIT/Apache.

Until a license lands: treat this as read-only learning material, don't publish derivatives.

## 1. Corrected findings (after reading the wiring)

Two earlier assumptions were wrong — corrected here:

- **The two Swift trees are NOT duplicates.** `ui/Sources/` is a SwiftPM modules package (`Core`/`UI`/`Networking`/`App`); `ui/Loom/` is the Xcode app target that consumes them. That's a normal library+app split, not duplication. Keep both.
- **The proxy IS auto-started and the session list IS wired.** `MainThreePaneLayoutView.onAppear` and `WelcomeView` call `LocalProxyLauncher.shared.startIfAvailable()`; `AppSettingsView` calls `.restart()` on save. `Sidebar.swift` bridges TCA selection back via `withDependencies { $0.sessionSelectionClient.select = ... }`.

The **real** issues, ranked:

| # | Issue | Evidence | Severity |
|---|---|---|---|
| 1 | **Split-brain state.** `TraceStore` (hand-rolled `ObservableObject`) is the real source of truth and does all polling/data. The TCA layer (`SessionListFeature` + `SessionSelectionClient`) is vestigial: `Sidebar` rebuilds `SessionListFeature.State` from `TraceStore` *every render* and only uses the reducer to fire a selection callback. TCA owns no state — you pay its complexity for none of its benefit. | `Sidebar.swift` `sessionListState` computed property; `SessionSelectionClient.liveValue = { _ in }` stub overridden per-render | High (architecture) |
| 2 | **Three product names baked into identifiers.** AgentTrace=20 files/82 lines, Loom=9/82 + loom=8/33, Tether=26/190. Load-bearing in env vars (`LOOM_*`), UserDefaults keys (`agenttrace.proxy.*`), JWT defaults (`agenttrace`), runtime paths. | repo-wide grep | High (confusion) |
| 3 | **Dead Postgres auth/settings layer.** Fully built (~30 KB across `auth/`, `settings.rs`, `crypto.rs`, `migrations/`) but `DATABASE_URL` is never set by the app, so all `/api/auth/*` + `/api/settings/*` return 503 in real use. | `LocalProxyLauncher.proxyEnvironment` omits `DATABASE_URL`; `AuthContext::from_env` returns `None` | High (dead weight / decision needed) |
| 4 | **Dead `App` module wrapper.** `AgentTraceAppEnvironment.startLocalProxyIfAvailable()` is never called — the app calls `LocalProxyLauncher.shared` directly. | no call sites in grep | Low |
| 5 | **Cost is a hardcoded `$0.0000` stub** everywhere; README markets "cost visibility." | `record_response`/`record_upstream_error` literal `"$0.0000"`; Codex observer too | Medium (missing feature) |
| 6 | **Codex observer couples to private Codex CLI internals** (`~/.codex/state_5.sqlite`, `logs_2.sqlite`, websocket log format), shelling to `/usr/bin/sqlite3`. Silent `nil` on breakage. | `CodexLogObserver` | Medium (fragility) |
| 7 | **No real test coverage.** Only `scripts/smoke-e2e.sh`. No Rust/Swift/JS unit tests. | repo | Medium |

## 2. Decisions (LOCKED 2026-06-12)

- **A. Canonical name → Tether, document the rest.** Keep internal `loom`/`LOOM_*` as a documented codename (renaming env vars risks the launcher↔proxy contract for no user benefit). Touch `agenttrace.*` keys only as part of the auth work (B is unaffected).
- **B. TCA → REMOVE.** Delete `SessionListFeature` + `SessionSelectionClient`, render the session list straight from `TraceStore`, drop the swift-composable-architecture SPM dep. Self-contained, no proxy changes.
- **C. Auth layer → INTEGRATE.** (Chosen against the park/delete recommendation — implies multi-user/team is on the roadmap.) This converts step 3 from a deletion into a real sub-project; see §3a for the open design questions that must be answered before coding it.

## 3a. Auth integration sub-plan (decision C) — OPEN DESIGN QUESTIONS

Integrating accounts into a **local-first, single-user macOS tool** has a real tension to resolve first: a proxy on `127.0.0.1` doesn't inherently need accounts. Before writing code, decide what auth is *for* and what it gates. Open questions:

1. **What does login actually gate?** Options: (a) cosmetic profile only; (b) settings move from local `UserDefaults` to server `user_settings` (sync across machines); (c) gates a future cloud trace-sharing/team feature. The README's pitch is local-first + Keychain secrets, which argues auth should be *optional* and additive, never required to use the proxy.
2. **Where does Postgres run?** A local-first desktop app can't assume a Postgres. Either (a) host a real backend (Tether becomes client+cloud, not just local), or (b) ship/bundle Postgres locally (heavy), or (c) port the auth schema to the SQLite the app already has (drops `sqlx`/Postgres, unifies on one datastore — likely the right move for desktop).
3. **Token storage** — README promises macOS Keychain. JWT/access token must land in Keychain, not `UserDefaults`. There's no Keychain code yet; this is net-new.
4. **Login UX** — the app has `WelcomeView` + `AppSettingsView` but no auth screens. Net-new SwiftUI: sign-in/up, OAuth round-trip handling, signed-out state.
5. **Does the local proxy require a token?** Today `/api/auth` + `/api/settings` are Postgres-gated but the trace/proxy paths are open. If accounts are added, decide whether `/api/traces/*` stays open (recommended for a localhost tool) or starts requiring the JWT.

**Recommended shape** (proposal, for discussion): keep the proxy/trace paths open and local; make accounts an *optional* layer; port auth+settings from Postgres to the existing SQLite (kill `sqlx`/Postgres); store the token in Keychain; settings sync is the first concrete payoff. This keeps "local-first" true while making the auth code actually reachable. **Confirm before building.**

## 3. Sequenced execution

Ordered so each step is independently shippable and low-risk. Steps 2/4/5/6/7/8 are decided and unambiguous — safe to start now. Step 3 (auth) waits on the §3a design questions.

1. **License** — add `LICENSE` once the author responds. _(blocks publishing, not work.)_
2. **Name unification** (~half day). One layer at a time, verifying both sides of each contract string:
   - Brand/UI strings → already Tether, leave.
   - `loom`/`LOOM_*` → **keep as internal codename, document it** (decision A). Renaming env vars has no user benefit and risks the launcher↔proxy contract.
   - `agenttrace.*` UserDefaults keys + JWT defaults → revisit during auth work (§3a). If keys move, write a one-time `UserDefaults` migration so existing installs don't lose settings.
3. **Auth integration (C)** — the sub-project from §3a. Gated on answering its 5 design questions. Largest single chunk of net-new work (datastore decision, Keychain, login UX). Do this *after* the cheap wins below so the codebase is clean first.
4. **Remove TCA (B)** — ✅ **DONE 2026-06-12.** Deleted `SessionListFeature.swift` + `SessionSelectionClient.swift`; rewrote `SessionListView` to take plain data (`sessions`/`selectedSessionId`/`liveSessionId`/`onSelect`) instead of `StoreOf<SessionListFeature>`; updated `Sidebar.swift` call site + removed `sessionListState` and the `withDependencies` bridge; dropped swift-composable-architecture from `Package.swift`; removed unused CA imports from `Sidebar.swift` + `MainThreePaneLayoutView.swift`. **Verified:** `swift build` (SPM modules) clean; CA + transitive deps gone from `ui/Package.resolved`; no TCA refs in source. **NOT verified:** the Xcode app target build — local `xcodebuild` is broken (`IDESimulatorFoundation` plug-in symbol mismatch; needs `xcodebuild -runFirstLaunch`). App-target changes were mechanical; confirm with a real Xcode build once the toolchain is fixed. The pbxproj needed no edits (it references only the local `LoomModules` package, not CA directly).
5. **Delete the dead `App` module wrapper** (#4) — trivial.
6. **Harden the Codex observer** (#6) — glob `~/.codex/state_*.sqlite` / `logs_*.sqlite` (pick highest version) instead of hardcoding `_5`/`_2`; surface a visible "Codex log format changed" state instead of silent `nil`.
7. **Real cost calc** (#5) — add a pricing table (per-model $/token in & out), compute from `tokens_in`/`tokens_out` at trace-record time in `trace.rs`. The token counts are already parsed; only the multiply+format is missing.
8. **Tests** (#7) — add Rust unit tests around the JSON normalization (`extract_prompt`, `extract_response_text`, `summarize_response`, `cache_key`) — they're pure functions and the riskiest logic. Keep extending `smoke-e2e.sh` for routing/caching.

## 4. What NOT to do

- **Don't rewrite the proxy.** The cache→tee→store streaming lifecycle and the crypto (PKCE, RS256 JWKS verify, AES-GCM) are correct and expensive to re-derive. The architecture (transparent proxy + local SQLite + native reader) is sound. This is a cleanup, not a rebuild.
- **Don't unify the names with blind find-replace** — env vars and UserDefaults keys are contracts; both sides must change together or persistence/launch silently breaks.
