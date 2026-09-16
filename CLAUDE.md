# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This repo contains **two independent codebases** that must not be mixed:

1. **`docs/`** — a static, framework-free "戰情室" (war room) dashboard demo site published via GitHub Pages (`main` branch, `/docs` folder, deploy-from-branch — no CI/build step).
2. **`warroom-data-api-prototype/`** — a real Ruby on Rails 8 app that is the *current* direction: it replaces the static prototype with live Google Sheets-backed pages and JSON APIs. This is a deliberate, spec-declared exception to the static-site rule (see `.kiro/steering/rails-standards.md`).

Work almost always happens in one or the other, not both. Check which directory a task's files live in before assuming which rule set applies.

Spec-driven development lives under `.kiro/specs/<spec-name>/` (`requirements.md`, `design.md`, `tasks.md`), governed by steering docs in `.kiro/steering/`. Read the relevant steering file(s) and the spec's `requirements.md` before implementing anything in either codebase — a spec's "技術棧說明" section can declare exceptions to the default rules (e.g. the Rails prototype opting out of the static/no-framework/no-external-API rules).

Root `project-rules.md` is a legacy, abbreviated copy of the `docs/` rules; `.kiro/steering/project-standards.md` is the canonical version (it also carries the exception clause and branch naming). Prefer the steering doc when they disagree.

## `docs/` — static site rules

From `.kiro/steering/project-standards.md` (applies to `docs/` only):

- Plain HTML/CSS/JavaScript only — no React/Vue/Angular, no Node.js/Vite/build tools, no external API calls.
- All data is hardcoded/mock (inline HTML or JS objects/arrays).
- UI language is Traditional Chinese (繁體中文).
- Must be responsive (desktop/tablet/mobile) via CSS media queries.
- All files live under `docs/`; GitHub Pages serves `main` branch `/docs` folder directly — no `.nojekyll`, no `gh-pages` branch, no workflow needed (see `.kiro/skills/github-pages-deploy.md`).

Run locally:
```bash
python3 -m http.server 8123 --directory docs
```

Structure: one HTML page + one JS module per dashboard view (`docs/index.html`, `issues.html`, `burndown.html`, `project-history-overview.html`, `project-phase-tracking.html`, `project-progress.html`), each paired with `docs/js/<name>.js`. Views whose mock dataset is large keep it in a sibling `docs/js/<name>-data.js` module (`project-history-data.js`, `project-phase-tracking-data.js`) so the view module stays render-only. Shared chrome (theme toggle) lives in `docs/js/entry.js`; single stylesheet `docs/css/style.css`.

Theme: dark is the default palette; light mode overrides CSS custom properties under `html[data-theme="light"]`. The Rails app repeats the same token scheme in its own `app/assets/stylesheets/application.css` — the two stylesheets are independent copies, so a theme change usually has to be made in both.

## `warroom-data-api-prototype/` — Rails app

Ruby 3.3.12, Rails ~8.1. Key gems: `service_actor`, `blueprinter`, `pagy`, `google-apis-sheets_v4`/`googleauth`, `importmap-rails`/`turbo-rails`/`stimulus-rails` + `propshaft` (no Node/bundler build step). **There is no database** — no `config/database.yml`, and `spec/rails_helper.rb` sets `config.use_active_record = false`. All state comes from Google Sheets plus `Rails.cache`.

### Commands

```bash
cd warroom-data-api-prototype
bin/setup                 # bundle install + log/tmp clear (no db step)
bin/rails server -p 3000  # run the app
bundle exec rspec                              # full test suite
bundle exec rspec spec/actors/sheets/fetch_project_progress_spec.rb   # single file
bundle exec rspec spec/actors/sheets/fetch_project_progress_spec.rb:42  # single example
bin/rubocop                # lint (Omakase Rails style)
bin/brakeman --no-pager    # static security scan
bin/bundler-audit          # gem vulnerability scan
bin/importmap audit        # JS dependency vulnerability scan
```
CI (`.github/workflows/ci.yml`) runs brakeman, bundler-audit, importmap audit, and rubocop on every push/PR — no rspec job is wired into CI, so run it manually before pushing.

### Mandatory layering (`.kiro/steering/rails-standards.md`)

Strict one-way flow, no skipping or reversing layers:

- **Controller** (`app/controllers/`) — calls one Actor, renders its output as JSON or hands it to the View. No data access, no external calls, no transformation logic.
- **Actor** (`app/actors/`, domain-namespaced: `app/actors/sheets/` for Sheets-backed fetches, `app/actors/summary/` for cross-source aggregation like `Summary::BuildExecutiveSummary`) — `service_actor` gem convention: single `call` entrypoint, inherits `ApplicationActor`, declares outputs via `output :xxx`. Owns business logic (fetch, normalize, validate, group).
- **Client** (`app/clients/`) — wraps exactly one external service call (e.g. `ProjectProgressSheetsClient` → Google Sheets API). Fetches raw data only; no business-layer transformation/validation. `GoogleSheetsCredentials` is the shared credential loader.
- **Blueprint** (`app/blueprints/`, Blueprinter gem) — single source of truth for output fields; Controller and View share the same Blueprint. Never redeclare a field list elsewhere.
- **View + Helper** (`app/views/<page>/`, `app/helpers/<page>_helper.rb`) — HTML pages are server-rendered ERB; charts (burndown lines, Gantt bars, KPI bars) are inline SVG generated by helpers. Helpers hold presentation math only (coordinate/scale/CSS-class mapping) and are the one place with real logic outside Actors — they have their own specs under `spec/helpers/`. Turbo/Stimulus is used sparingly (`app/javascript/controllers/`); most interactivity is plain query-param links handled by the Controller.

Errors are always shaped `{ "error": { "code": "<code>", "message": "<desc>" } }`. Actors fail via `fail!(failure_code: :xxx, message: "...")`; Controllers map `failure_code` → HTTP status: `sheet_not_found`→404, `access_denied`→403, `invalid_data_format`→422, `internal_error`→500 (extend this table per-spec as needed).

### Sheets caching

Every Sheets client wraps its API call in `Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY)` with `CACHE_EXPIRY = 5.minutes` — the cache sits in the Client layer, never in Actors or Controllers. Notes:

- Exceptions are not cached, so a failed fetch retries on the next request and never clobbers a good cached value.
- `ProjectProgressSheetsClient` additionally supports `fetch_rows(force: true)` plus a `.../fetched_at` key for the "重新整理資料" button: `/dashboard?refresh=1` → Controller passes `force:` into `Sheets::FetchProjectProgress` → Client. Other clients deliberately have no force/fetched_at (see the comments in `phase_records_sheets_client.rb`); don't add one speculatively.
- `config.cache_store` is `:memory_store` in development and `:null_store` in test — so caching is inert under rspec unless a spec stubs `Rails.cache` explicitly.

### Google Sheets integration conventions

- Credentials load order: Rails encrypted credentials (`Rails.application.credentials.dig(:google_sheets, :service_account_json)`, preferred for local dev) → env var `GOOGLE_SHEETS_CREDENTIALS_JSON` (CI/deploy) → missing → Actor fails with `internal_error`. Never hardcode credentials in source.
- Auth scope is always read-only (`spreadsheets.readonly`).
- Sheets API responses come back tagged `ASCII-8BIT` even when valid UTF-8 — re-tag with `force_encoding(Encoding::UTF_8)` before concatenating with Chinese string literals, or you'll hit `Encoding::CompatibilityError`.
- Sheets API omits trailing blank cells in a row — pad rows to a fixed column count before mapping fields, or fields shift.
- A record missing a required field is skipped individually; it must never fail the whole request (real sheet data has occasional incomplete rows).
- If date normalization fails, keep the raw string value rather than raising or treating it as `invalid_data_format`.
- Spreadsheet/tab IDs that rotate yearly are read from env vars with a hardcoded fallback default rather than derived from the system date. Authoritative list is the `ENV.fetch` calls in `app/clients/` — currently `PROJECT_PROGRESS_SPREADSHEET_ID`, `BURNDOWN_SHEET_NAME`, `PROJECT_ROSTER_SHEET_NAME`, `PROJECT_PROFILES_SHEET_NAME`; the README table documents only the first two, so update it when adding one.
- New worktrees need `config/credentials/development.key` copied in manually (it's gitignored and per-checkout); copy it from the primary checkout rather than regenerating.

### Testing conventions

`spec/` mirrors the layers (`actors/`, `clients/`, `blueprints/`, `controllers/`, `helpers/`, `requests/`). No WebMock/VCR: Actor specs stub the Client class method directly (`allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(rows)`), and Client specs stub the Google API service object. `ActiveSupport::Testing::TimeHelpers` is included globally — use `travel_to` for anything comparing against "today" (overdue/this-week logic is everywhere).

### Current routes

`/` (home), `/dashboard` (305 project progress), `/issues` (306 bug issues), `/burndown` (307 hour burndown), `/project_history`, `/project_phase_tracking`, `/executive_summary` (cross-source weekly summary); JSON API under `/api/project_progress`, `/api/issue_dashboard`.

## Spec workflow (both codebases)

- `.kiro/skills/karpathy-guidelines.md` is the active house style: simplest solution that satisfies requirements, no speculative abstraction (wait for ≥3 concrete use cases), state a verifiable acceptance criterion before implementing, verify against it before calling a task done, prefer editing over adding files, delete dead code outright.
- Read a spec's `requirements.md` + `design.md` and the applicable steering doc(s) before coding; `tasks.md` tracks checkbox-level progress and often includes a task dependency wave graph.
- Specs come in pairs: `*-static-prototype` specs built the `docs/` page, and the matching `*-real-source` spec ported it to Rails + live Sheets. When changing a Rails page, its `-real-source` spec is the relevant one.
- Branch naming: `<type>/<short-description>` (all lowercase, hyphenated), type ∈ `feature|fix|chore` — see `.kiro/steering/project-standards.md`.
- `.kiro/hooks/frontend-quality-review.json` and `.kiro/hooks/rails-backend-quality-review.json` define read-only PostFileSave review checklists (semantic HTML/responsive CSS/forbidden-tech for `docs/*.{html,css,js}`; service_actor/Blueprinter/RSpec coverage/N+1/rubocop for `*.rb`/`*.erb`) — worth applying manually as a self-check even outside the hook trigger.
