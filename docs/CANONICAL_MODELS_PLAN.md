# Canonical models — plan

Status: **not started / deprioritised.** Interim workaround is retiring duplicate
rows by hand in the admin (see "Interim" at the end). This doc is the build
checklist for when it's picked up.

## Problem

OpenRouter lists many rows per *logical* model — a GA row plus a `Preview`, plus
dated snapshots (`GPT-4o (2024-08-06)`), plus namespace variants that collide
with our curated rows (`openai/o3-pro` vs the curated `o3-pro`). We ingest the
*listing* layer with no *model* layer on top, so the catalogue fills with
near-identical rows. The current defence is reactive: `retire_alias_duplicates`
(see `OpenRouter::ModelSync`) retires same-priced trailing-suffix twins. It only
catches a subset — it misses internal markers (`Nano Banana 2 (… Image
Preview)`), punctuation differences (`Qwen Plus 0728` vs `Qwen-Plus`), and
cross-source collisions (`o3 Pro` vs `o3-pro`) — and *retiring* a dated snapshot
throws away its price history, which is this site's core asset.

## Idea

Model the domain as **one canonical model with many variant listings**. Default
views show canonical rows only; variants stay active and priced in the DB,
hidden from listings and reachable behind the canonical (and by direct URL). This
subsumes the dedup heuristic, the `:latest`/`:fast` handling, and the
preview/dated handling into one framework, and preserves all price history.

It also sets up two later wins: the canonical row is the right unit to hang a
future **benchmark** score on, and the DB grouping maps directly onto an HTML
`rel="canonical"` for SEO.

## Step 1 — canonical flag + listing filter (this doc)

Non-goal for Step 1: the versions/variants UI, cross-provider grouping,
benchmarks. Step 1 just picks a canonical per group and hides the rest from
collection views.

### Data model

Two columns on `ai_models`:

- **`canonical_id`** — nullable FK to the `ai_models` row that is this listing's
  canonical model. `nil` ⇒ this row *is* canonical (or standalone).
  - `belongs_to :canonical, class_name: "AiModel", optional: true`
  - `has_many :variants, class_name: "AiModel", foreign_key: :canonical_id`
  - `def canonical? = canonical_id.nil?`
- **`canonical_locked`** (boolean, default false) — a human set the grouping; the
  sync must not recompute it. Mirrors the "curated data is authoritative" rule.

No `logical_model` table — the grouping lives on the rows, which keeps Step 1
small and gives the Step 2 versions view (`canonical.variants`) for free.

### Grouping rules (which listings are one logical model)

Computed by a `ModelCatalog::Canonicalization` PORO (plain domain object: takes
the catalogue, returns `{variant_id => canonical_id}`), invoked by `ModelSync`.
Conservative, so canonical-filtering never *hides* a distinct model:

1. **Same provider only.**
2. **Strip only marker tokens**, then compare the residue char-for-char
   (lowercased, punctuation collapsed). Markers:
   - `preview`
   - date-pins: `YYYY-MM-DD`, `MM-DD`, `MM-YYYY`, `YYYYMMDD`, and a bare 4-digit
     that parses as `MMDD`/`YYMM` (`0728`, `0905`, `2512`).
3. **Group iff the residue is identical.** Examples:
   - `Gemini 3.1 Pro` ↔ `Gemini 3.1 Pro Preview` → group
   - `o3 Pro` ↔ `o3-pro` → residue `o3 pro` → group (cross-source)
   - `Qwen Plus 0728` ↔ `Qwen-Plus` → residue `qwen plus` → group
   - `GPT-4o (2024-05-13)` ↔ `(2024-08-06)` → residue `gpt 4o` → group
   - `GPT-5` ↔ `GPT-5 Codex` → residue differs (`codex`) → **distinct**
   - `Claude Sonnet 4.5` ↔ `4.6` → residue differs, not a date-pin → **distinct**
4. **When unsure, don't group.** The one ambiguous spot is a bare 4-digit that
   could be a version rather than a date — leave ungrouped, let a human override.

### Canonical selection within a group

Deterministic, stable (no churn):

1. Curated (`source: "manual"`) over imported.
2. GA over `preview`.
3. Latest date (undated, else newest date-pin).
4. Tie-break: newest `released_on`, then shortest name, then lowest `id`.

Winner gets `canonical_id = nil`; the rest point at it. `canonical_locked` rows
are left exactly as set.

### Listing behaviour

Add `scope :canonical, -> { where(canonical_id: nil) }`. Apply it to
**collection** reads only — **do not** overload `.listed` (see gotcha).

- Variants stay `status: "active"` and priced — *not* retired.
- Retiring goes back to meaning only "the provider killed it."

## Touch-point map (the full ripple)

### Creation / ingestion paths

| Path | Change |
|---|---|
| `OpenRouter::ModelSync` | Replace `retire_alias_duplicates` with `resolve_canonicals`. Set `canonical_id` **per-row at import** (reuse the `catalog_siblings` machinery `alias_duplicate?` already uses) so editorial/digest can gate immediately, **plus** a sweep pass to re-resolve existing rows. `alias_duplicate?` flips from *skip-the-row* to *create-and-attach*. `curated_duplicate?` stays as a best-effort skip; the sweep catches stragglers. |
| `ModelCandidate::Acceptance` (#135 queue) | Run canonical resolution on the newly-created row. Upgrade the reviewer's dedup hint (`existing_model`, currently exact-slug) to the fuzzy residue match — "looks like a variant of X". |
| `Admin::ModelsController` + form | Permit + edit `canonical_id` / `canonical_locked`; let an admin attach/detach or promote a row. |
| `db/seeds.rb` | Curated rows default canonical (`nil`). Only set `canonical_id` if a seed intentionally lists a variant (rare). |

### Read paths that switch to `.canonical`

All currently consume `.listed` / `PriceCatalog.models`:

- models table + category counts + `@all_models_count` (`ModelsController`)
- `@related` models on the show page
- sitemap (`SitemapsController`)
- public API (`Api::V1::ModelsController`)
- compare picker `@all_models` (`ComparisonsController`)
- learn `@catalog` (`LearnController`)
- hero events `build_all_events` (`EventsHelper`)
- recent-price-changes strip (`PriceCatalog.recent_price_moves`) — else a dated
  pin's reprice spams the feed

### The gotcha — detail lookups must NOT be canonical-filtered

`ModelsController#show` finds by slug (`find_by!`), so a variant page resolves —
but it then calls `PriceCatalog.model(@model.slug)`, which looks up *through
`.listed`*. If `.listed` were canonical-filtered, `@catalog_entry` would be `nil`
and every variant's detail page would break. Therefore:

- `PriceCatalog.model(slug)`, the show `find_by`, and routing must resolve **any**
  row (canonical or variant) — variant deep links / backlinks stay 200.
- This is *the* reason to add a separate `.canonical` scope rather than
  overloading `.listed`.

### Behaviours that should skip variants (need per-row resolution at import)

- **Editorial generation** — don't spend Anthropic calls on hidden dated pins.
- **Slack digest "new models"** + **social `launch_posts`** — a pin/preview isn't
  a launch; announce canonical only.
- **Market-event / launch cards** — a variant shouldn't mint a launch card.

### SEO

- Variant show pages emit `rel="canonical"` → their canonical model page.
- Sitemap goes canonical-only via the scope swap (stops submitting dup URLs).

## Migration / rollout

- Add the two columns; backfill by running canonicalization once.
- Rows previously retired by the old sweep that are actually variants get
  **un-retired and re-pointed** to their canonical, restoring their history
  behind the canonical.
- The confirmed same-price dups resolve automatically — no manual admin retiring.

## Open decisions

1. **Search** — should typing a dated pin's exact name find it, though the table
   is canonical-only? Lean: **no** — reach variants via the versions view (Step 2)
   and direct URL; keep search canonical-only for a clean result set.
2. **`:latest` / `:fast` aliases** — fold into canonical (become variants) or keep
   retiring them? They carry no unique price history, so lean: **keep retiring**
   and reserve canonical for rows worth preserving.
3. **Already-retired variants** — un-retire and re-point (restores history) or
   leave retired? Lean: **un-retire** — preserving data is the whole point.

## Risks

- **Over-grouping** hides a distinct model → mitigated by residue-identical +
  markers-only + "unsure → don't group" + `canonical_locked` override.
- **Count / SEO shift**: the public "N models" count drops to canonical-only —
  correct, and `rel="canonical"` + 200-resolving variant slugs protect links.

## Interim (until this ships)

Retire duplicate rows by hand in the admin (`…/admin/models/<slug>/edit` → status
Retired). The same-priced duplicate groups are detectable from the public API
(`/api/v1/models.json`) by normalising names (strip `preview` + date tokens) and
grouping same-provider rows with an identical residue and identical price. This
list drifts as the daily sync runs, so regenerate before a cleanup pass.
