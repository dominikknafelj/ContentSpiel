# Image Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every library image shows at once and never moves the text: its size and a blurred preview are known from the upload, re-encoded widths are made on a queue of their own, the public never gets the original, every image address is public, immutable and cacheable, and an image change moves the content version only when a live page can show it.

**Architecture:** One decode at validation (`Media::Decoding`) gives every new asset its `width`, `height` and a ~24px WebP preview stored on the row. One job per image (`Media::RenditionJob`, queue `images`) makes the widths `ImageSettings` names and records the finished generation on the asset (`renditions`, `renditions_fingerprint`), which `Media::Asset#srcset`/`#src` read instead of `variant_records`. Active Storage runs in proxy mode globally; two concerns beside the note-file refusal keep a library original and an unmade variant out of the public routes. Settings → Images edits `ImageSettings`' columns; "Regenerate images" is `Media::Regenerate`.

**Tech Stack:** Rails 8.1 (Active Storage 8.1, `http_cache_forever` already writes `public, max-age=3155695200, immutable`), ruby-vips / image_processing, Solid Queue, ViewComponent, Stimulus (site entry point), Minitest with Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-31-image-delivery-design.md` (owner-approved 2026-10-31). Read it whole before any task; decisions are cited below as "D1"…"D8".

## Global Constraints

- Work only in `/Users/dknafelj/src/ContentSpiel-image-delivery` (branch `image-delivery`). Its test database is the folder's own (`ContentSpiel::TestDatabase`); Task 1 runs `bin/rails db:test:prepare` once.
- Every test command is prefixed `PGGSSENCMODE=disable`. A system test needs `bin/rails tailwindcss:build` first (never while tests run) and runs as `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test <file>`. Check `sysctl -n vm.loadavg` before the browser suite.
- Never the original to the public (owner): no `src`, `srcset` candidate, MCP answer or public route serves a library asset's original file. Signed-in editors download it only through CS Studio (Task 7).
- No request makes a variant; no page waits for a width; no wrapper element around the `<img>`; no class added inside rendered rich text; nothing hidden by CSS alone (spec "Anti-goals").
- Default settings: format `webp`; quality 75 for WebP and 50 for AVIF (libvips' own defaults, so a site that changes nothing gets the images it has); widths `[480, 960, 1600, 2400]`; largest upload 10 MB. Bounds: 1–6 distinct widths, each 160–4,000; quality 1–100; largest upload 1–50 MB.
- Widths made for an image (D3): every configured width below the original's width, plus one at `min(original width, largest configured width)`; distinct, ascending.
- Preview: WebP about 24px wide, made from the same decode as the dimensions, stored on `media_assets`; its blur is the Design System's (question 1/2), made in the image by the server.
- Queue `images`: Active Storage's `analysis` and `transform` queues, `Media::RenditionJob` and `Media::BackfillJob`; one thread, polling every 2 s. Every other job stays on `default`.
- Every `update_columns` / `update_all` on `media_assets` carries `# version: none (reason)` or bumps (`test/lib/version_bump_test.rb`). The conditional bump says so on its line.
- New `site_settings` columns join `Audit::Snapshot`'s lists as settings (audited); `preview`, `renditions`, `renditions_fingerprint`, `renditions_failed_at`, `renditions_error`, `has_alpha` on `media_assets` are derived: in `NEVER_STORED` (preview, renditions) or `IGNORED_CHANGES` (the rest).
- Words: CS Studio's new strings are keys (`docs/reference/i18n.md`; a component's under `config/locales/admin/<folder>.en.yml`); a model's validation messages are `activerecord.errors.models.media/asset.attributes.file.*` in `config/locales/en.yml` (Ruling 6); System status rows are written as their neighbours are. The public site gains no words.
- The looks (spec "Questions for the Design System", 1–8) are not decided by this plan and no answers file exists yet. Build every screen from existing components and tokens with every word in a key; the controller takes the eight questions to the Design System before the PR (the owner's rule: never decide UI alone) and the answers land as a follow-up commit.
- Code comments in the files this work rewrites state invariants, never "Task N", "fix round" or "Review Focus" (spec, the review's finding).
- Do not run a build while tests run; do not push.

## Rulings made while planning (spec gaps)

1. **A generation records each width's variation KEY, not only its digest.** D5 says "its width and its variation digest"; an address is the blob's signed id plus the signed variation key, which a digest cannot rebuild. Each file is `{ "width", "key", "digest" }`: the key builds the proxy URL (`rails_blob_representation_proxy_path`), the digest is what the 404 concern and the cleanup compare. Cost if wrong: none; the digest is kept too.

> **Owner's decision, 2026-10-31, overrides Rulings 2 and 3 and Task 6's fade:** there is no fade and no script. The image is one `<img>` whose background is the preview; the browser draws the sharp image over it as it arrives. Drop `image_fade_controller.js`, its `site` registration, `data-controller="image-fade"`, `data-image-loading`, the `transition`, the scrubber's keep of the fade's attribute and the fade's tests (the reduced-motion test and the `public_javascript_test` line). Keep `data-image-preview` and `data-image-empty`. Task 6's commit message drops "and fades it in".

2. **The fade is an un-blur, not an opacity cross-fade.** With one `<img>` (anti-goal) whose own background is the preview, fading the image's opacity fades its background with it. The script's attribute (`data-image-loading`) gives the loading image the preview's look through `filter`, and removing it transitions `filter` to none. If the Design System insists on a true cross-fade, that needs a wrapper and reopens the anti-goal: say so with question 2. Cost if wrong: the CSS of Task 6 and its system test.
3. **The fade's controller is top-level but registered by `site` only.** `controllers/index.js`'s default set (which CS Studio's `admin` entry also registers) leaves out `controllers/image_fade_controller` by name (`SITE_ONLY`), and `app/javascript/site.js` registers it. Identifier `image-fade`. Cost if wrong: one filter.
4. **The deploy-time backfill is a recurring job, not a one-off enqueue.** A migration cannot reliably enqueue into the queue database. `Media::BackfillJob` (queue `images`, every 10 minutes in `config/recurring.yml`) makes the missing previews and dimensions; on a site with none missing it is one indexed `exists?`. Cost if wrong: one entry.
5. **One download per width, through Active Storage's own `variant.processed`**, not D5's "one download of the original": reimplementing `VariantWithRecord`'s record and attachment is Rails internals; on the Disk service a download is a local copy. Cost if wrong: measured in Task 12; a later change inside the job only.
6. **Model refusals are Active Record messages** (`:too_large` with `%{size}`, `:unreadable`, `:too_many_pixels`) in `config/locales/en.yml`, not under `config/locales/admin/`: `Media::Asset` is below CS Studio (`test/lib/dependency_direction_test.rb`), and MCP and the import read the same messages.
7. **A pixel cap.** The spec is silent on a decompression bomb under the byte limit. `Media::Decoding::MAX_PIXELS = 100_000_000` (100 megapixels); over it the upload is refused ("This image is too large to process"), before libvips decodes the pixels. Cost if wrong: one constant.
8. **No preview background for an image with an alpha channel** once its widths exist (`has_alpha`), or the blurred preview would show through its transparent parts for ever. It still gets the preview as `src` while no width exists. Cost if wrong: one column and a condition.
9. **`renditions_fingerprint` is a column of its own** beside `renditions`, so the progress counts and Regenerate's selection are hash conditions, not jsonb operators. The fingerprint is `Digest::SHA256.hexdigest` of the format, quality and widths as JSON (not an HMAC: nothing in it is secret).
10. **"Download original" is `Admin::MediaOriginalsController#show`**, not the blob proxy: Active Storage's proxy controllers include `ActiveStorage::DisableSession`, so they cannot tell an editor from a visitor. The blob routes refuse a library original to everyone.
11. **The adopted generation's fingerprint** is the default settings' only if a width made with today's transformations carries no camera data (Task 9 checks it with a JPEG carrying GPS). If it does, the adopted generation is recorded under the fingerprint `"adopted"`, so the card counts those images as made with other settings and Regenerate replaces them. `docs/reference/media.md` records which.
12. **`with_variants` / `VARIANT_INCLUDES` become `with_file` / `FILE_INCLUDES`** (`{ file_attachment: :blob }`): the generation is on the row, so no list preloads `variant_records` any more.
13. **Measuring.** If the documentation site's server cannot be reached from the session, Task 12 writes the procedure and the local figures into `media.md` and leaves the documentation site's figures to the owner, said in the PR.

## Review Focus

1. A phone photo with EXIF orientation 6 (portrait shot stored landscape): expected `width`/`height` of the image as shown (rotated), and widths and preview of that shape. Test in Task 2.
2. An image with transparency (a logo-like PNG on the library): expected no blurred preview showing through it after it loaded. Test in Task 6 (Ruling 8).
3. Settings → Images saved with widths typed out of order or twice ("960, 480, 480"): expected out of order sorted, a duplicate refused with a sentence, nothing saved. Test in Task 10.
4. Regenerate pressed, then the format changed and saved again before the queued jobs ran: expected every image made once, with the newest saved settings, never the older ones. Test in Task 4.
5. A PNG under 10 MB that is 20,000 × 20,000 pixels: expected refused with a sentence, the request returning, no server memory blown. Test in Task 2 (Ruling 7).

---

### Task 1: Setup, the settings columns and `ImageSettings`

**Files:**
- Create: `db/migrate/<ts>_add_images_to_site_settings.rb`, `app/values/image_settings.rb`, `test/values/image_settings_test.rb`
- Modify: `app/models/site_setting.rb` (validations of the bounds), `db/schema.rb`, `app/models/audit/snapshot.rb` (nothing to add: the columns are settings; confirm `IGNORED_CHANGES` leaves them in)

**Interfaces:**
- Produces: columns `image_format` (string, default `"webp"`, null false), `image_quality_webp` (integer, default 75), `image_quality_avif` (integer, default 50), `image_widths` (jsonb, default `[480, 960, 1600, 2400]`), `image_max_upload_mb` (integer, default 10).
- Produces: `ImageSettings.current(site = Current.site || SiteSetting.instance) -> ImageSettings` (use the app's existing accessor for the settings row); `#format -> "webp" | "avif"`; `#quality -> Integer` (the chosen format's); `#widths -> Array<Integer>` (ascending); `#max_bytes -> Integer`; `#fingerprint -> String`; `ImageSettings.avif_available?(probe: AVIF_PROBE) -> Boolean` (memoised per process; probe writes a 4×4 image with `heifsave` `compression: :av1`, rescuing every error to false); constants `DEFAULTS`, `WIDTH_RANGE = 160..4000`, `WIDTH_COUNT = 1..6`, `QUALITY_RANGE = 1..100`, `UPLOAD_MB_RANGE = 1..50`.

- [ ] **Step 1: Prepare the worktree:** `bin/setup --skip-server` if gems are missing, then `PGGSSENCMODE=disable bin/rails db:test:prepare`. Expected: exit 0.
- [ ] **Step 2: Write the failing tests** in `test/values/image_settings_test.rb`:
  - "a site that changed nothing has webp at 75, the four widths and 10 MB" (`max_bytes == 10.megabytes`).
  - "the fingerprint changes with the format, the chosen format's quality and the widths, and with nothing else" (changing `image_quality_avif` while WebP is chosen, or `image_max_upload_mb`, leaves it; it is 64 hex characters).
  - "the bounds are refused on the row": 0 and 7 widths, a width of 159 and 4,001, quality 0 and 101, 51 MB, an unknown format → `SiteSetting#valid?` false with an error on the column.
  - "avif is unavailable when the probe raises" (`ImageSettings.avif_available?(probe: -> { raise Vips::Error })` false).
- [ ] **Step 3: Run** `PGGSSENCMODE=disable bin/rails test test/values/image_settings_test.rb`. Expected: FAIL (no `ImageSettings`).
- [ ] **Step 4: Write the migration, the validations and `ImageSettings`.** Widths are stored sorted; a duplicate is a validation error (Review Focus 3 is tested through the screen in Task 10).
- [ ] **Step 5: Run** the file and `PGGSSENCMODE=disable bin/rails test test/models/site_setting_test.rb test/models/audit`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: image settings on the site row, with their fingerprint`.

### Task 2: One decode at validation: size, preview, refusal

**Files:**
- Create: `db/migrate/<ts>_add_preview_and_renditions_to_media_assets.rb`, `app/values/media/decoding.rb`, `test/values/media/decoding_test.rb`, fixtures `test/fixtures/files/rotated.jpg` (orientation 6, GPS EXIF), `transparent.png`, `animated.gif` (3 frames), `not_an_image.png` (PNG signature, broken body), `huge_pixels.png` (20,000 × 20,000, small on disk: one colour, compressed)
- Modify: `app/models/media/asset.rb` (validation and `cache_metadata_from_file`), `app/services/media/upload.rb` (remove `analyze_dimensions` and its bump), `config/locales/en.yml`, `app/models/audit/snapshot.rb`, `db/schema.rb`, `test/models/media/asset_test.rb`, `test/services/media/upload_test.rb`, `test/models/rich_text/html_import_test.rb` (or wherever `create_asset` is tested)

**Interfaces:**
- Consumes: `ImageSettings.current.max_bytes` (Task 1).
- Produces: columns on `media_assets`: `preview` (binary), `has_alpha` (boolean, default false, null false), `renditions` (jsonb, default `{}`, null false), `renditions_fingerprint` (string, indexed), `renditions_failed_at` (datetime), `renditions_error` (string). No `NOT NULL` on `width`/`height` (D1).
- Produces: `Media::Decoding.read(io, content_type:) -> Media::Decoding::Result` (`Data.define(:width, :height, :preview, :alpha)`); raises `Media::Decoding::Unreadable` or `Media::Decoding::TooManyPixels`. Reads the header first (`Vips::Image.new_from_buffer`/`new_from_file` with `access: :sequential`), refuses `width * height > MAX_PIXELS` before any pixel is decoded, applies `autorot`, takes one frame's height for an animated image (`page-height`), and makes the preview as `thumbnail` to `PREVIEW_WIDTH = 24` from the first frame, saved WebP with `strip: true`. `MAX_PIXELS = 100_000_000`.
- Produces: `Media::Asset` validates on `file_changing?` through `with_attachable_io`: `:too_large` (`size:` from `ImageSettings`), the type rules as today, then `:unreadable` / `:too_many_pixels`; `before_save` writes `width`, `height`, `preview`, `has_alpha` from the result. The byte sniff runs first: a file the sniff refuses is never decoded.

- [ ] **Step 1: Write the failing tests:**
  - `decoding_test.rb`: "a rotated photo has the size it is shown at" (rotated.jpg's width < height; Review Focus 1); "the preview is a WebP 24 pixels wide with no camera data" (`Vips::Image.new_from_buffer(preview, "")` width 24, `get_fields` holds no `exif-data`); "an animated GIF's height is one frame's and its preview its first frame"; "a transparent PNG says it has alpha, a JPEG does not"; "a file with an image's signature that cannot be decoded is Unreadable"; "over 100 megapixels is refused before the pixels are read" (huge_pixels.png raises `TooManyPixels`, and with `capture` of `Vips` cache stats or a timing bound under 1 s; Review Focus 5).
  - `asset_test.rb`: replace the 10 MB tests with "a file over the site's largest upload is refused with its size in the sentence" (set `image_max_upload_mb: 1`, a 1.1 MB PNG; message includes "1 MB"); "a file that cannot be read as an image is refused: This file can't be read as an image" and "nothing is kept"; "a saved asset has its width, height and preview before the save commits" (no job performed); drop the srcset/variant tests here (Task 3 rewrites them).
  - `upload_test.rb`: "an upload that cannot be decoded is a failure with the sentence, and no asset or blob row remains attached" (the version tests are Task 5's).
  - The HTML import's test: "an imported image that cannot be decoded is reported, not kept" and "an imported image has its size".
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/values/media/decoding_test.rb test/models/media/asset_test.rb test/services/media/upload_test.rb`. Expected: FAIL.
- [ ] **Step 3: Write the migration, `Media::Decoding`, the validation and the locale keys** (`too_large: "must be %{size} or smaller"`, `unreadable: "can't be read as an image"`, `too_many_pixels: "is too large to process (over 100 megapixels)"`; the full messages read "File can't be read as an image" as Active Record joins them: check the sentence the tile shows in `Admin::MediaUploadResponses` and adjust the attribute's human name if it reads wrong). Remove `Media::Upload#analyze_dimensions` and its `PublicSite.bump_version!`. Add `preview` and `renditions` to `Audit::Snapshot::NEVER_STORED`, the other four columns to `IGNORED_CHANGES`.
- [ ] **Step 4: Run** the three files, `test/models/rich_text`, and `PGGSSENCMODE=disable bin/rails test test/lib/version_bump_test.rb test/lib/dependency_direction_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: an image's size and preview from one decode at upload, and a file that is no image refused`.

### Task 3: The generation, and what an asset answers

**Files:**
- Create: `app/values/media/renditions.rb`, `app/values/media/generation.rb`, `test/values/media/renditions_test.rb`, `test/support/media_renditions.rb` (`make_renditions!(asset)`: runs the job of Task 4 inline once it exists; until then writes a generation through `Media::Generation` for given widths)
- Modify: `app/models/media/asset.rb` (remove the `has_one_attached` variant block, `VARIANT_WIDTHS`, `#variable_image?`, `#url`, `processed_variant_digests`; rename `with_variants`/`VARIANT_INCLUDES` to `with_file`/`FILE_INCLUDES` = `{ file_attachment: :blob }`), every caller listed by `grep -rnE "with_variants|VARIANT_INCLUDES" app lib` (pages/editing/media/trash controllers, `PublicPageRendering#preload_page_images`, `RichText::RenderContext`, `Media::Search`, `Admin::MediaFields`, the two MCP tools), `test/models/media/asset_test.rb`, `test/test_helper.rb`

**Interfaces:**
- Produces: `Media::Renditions.widths_for(original_width:, configured:) -> Array<Integer>` (Global Constraints' rule); `Media::Renditions.transformations(width:, format:, quality:, content_type:) -> Hash` (`resize_to_limit: [width, nil]`, `format:`, `saver: { quality:, strip: true }`, and `loader: { n: -1 }` for `image/gif` and `image/webp`, so an animation keeps every frame).
- Produces: `Media::Generation.from(hash) -> Media::Generation | nil`; `#fingerprint`, `#files -> Array<{width:, key:, digest:}>` ascending, `#to_h`. `asset.renditions` holds `{ "current" => generation, "previous" => generation }`.
- Produces on `Media::Asset`: `#srcset -> Array<[String, Integer]>` (url, width) of the current generation, empty without one, no query; `#src -> String | nil` (the made width at index `(n - 1) / 2`, else `#preview_data_url`, else nil); `#preview_data_url -> String | nil` (`"data:image/webp;base64,…"`, strict base64); `#display_url(min_width:) -> String | nil` (smallest made width ≥ `min_width`, else the largest made, else the preview, else nil); `#thumbnail_url` = `display_url(min_width: 480)`; `#made?` (a current generation exists); `#made_with?(fingerprint)`. URLs through `Rails.application.routes.url_helpers.rails_blob_representation_proxy_path(signed_blob_id: file.blob.signed_id, variation_key: key, filename: file.filename, only_path: true)`.

- [ ] **Step 1: Write the failing tests:**
  - `renditions_test.rb`: "an image wider than the largest width gets every width and the largest once" (2,880 → `[480, 960, 1600, 2400]`); "an image between widths gets the ones below and its own" (1,000 → `[480, 960, 1000]`); "an image narrower than the smallest width gets one width, its own" (300 → `[300]`); "an animated format keeps its frames, a still one has no loader option".
  - `asset_test.rb`: "with no generation srcset is empty and src is the preview, never the original" (assert no `src`/candidate contains the blob's own signed id path `/blobs/`); "with no generation and no preview src is nil"; "with a generation srcset lists exactly its widths as proxy representation addresses and src is the middle one"; "the srcset of fifty assets loaded with with_file costs no query" (`capture_sql`, as the existing test does); "display_url takes the smallest width that covers, else the largest, else the preview".
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/values/media/renditions_test.rb test/models/media/asset_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the two values and the asset's readers; rename the scope at every caller; rewrite the asset's comments about variants, `srcset` and the upload as the invariants they now are. Leave `Media::PictureComponent` reading `#srcset`/`#src` as it does (Task 6 rewrites it), but delete its "original as widest candidate" line now, since the original is no longer reachable.
- [ ] **Step 4: Run** `PGGSSENCMODE=disable bin/rails test test/models/media test/components test/controllers test/integration/admin/media_test.rb test/integration/mcp_media_test.rb`. Expected: PASS once callers are renamed (a failure naming `with_variants` is a caller missed).
- [ ] **Step 5: Commit** `ref: an asset's widths come from its recorded generation, never from the original`.

### Task 4: The job, its queue and its telemetry

**Files:**
- Create: `app/jobs/media/rendition_job.rb`, `test/jobs/media/rendition_job_test.rb`, `test/lib/job_queues_test.rb`
- Modify: `config/application.rb` (`config.active_storage.queues.analysis = :images`, `.transform = :images`, `.purge = :default`, `.mirror = :default`), `config/queue.yml`, `app/models/media/asset.rb` (`after_create_commit` enqueue), `app/services/trash/restore.rb` (enqueue on a media restore when not `made_with?` the current fingerprint), `config/initializers/public_site_version.rb`, `test/support/media_renditions.rb`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `Media::RenditionJob.perform_later(asset)`; `queue_as :images`; `perform(asset)` reads `ImageSettings.current` AT PERFORM TIME (never a fingerprint from the arguments: Review Focus 4). It skips a trashed asset; makes the preview, dimensions and `has_alpha` when missing (`Media::Decoding` on `file.blob.open`); returns if `made_with?(fingerprint)`; else makes each width smallest first through `file.variant(transformations).processed`, then one `update_columns(renditions: { "current" => new, "previous" => old_current }, renditions_fingerprint:, renditions_failed_at: nil, renditions_error: nil)` with its `# version:` line, then destroys the variant records of the generation before `old_current` whose digests are in neither kept generation, then bumps under Task 5's rule (until Task 5 lands, bump unconditionally and leave the comment saying it narrows there).
- Produces: `retry_on StandardError, attempts: 3, wait: :polynomially_longer`, and after the last attempt `update_columns(renditions_failed_at: Time.current, renditions_error: error.class.name)` (class only, never a message). `Media::Decoding::Unreadable` is recorded at once with no retry.
- Produces: span attributes on the job's consumer span (`OpenTelemetry::Trace.current_span`): `image.queue_latency_ms` (`Time.current - enqueued_at`), `image.width.<w>.ms` per width, `image.bytes_in`, `image.bytes_out`; no file name, no path.
- Produces: `config/queue.yml` workers: `- queues: "default"`, threads 3, polling 1 (as today), and `- queues: "images"`, threads 1, processes 1, `polling_interval: 2`.
- Produces: `config/initializers/public_site_version.rb` bumps for a variant record unless its blob is a library file (`ActiveStorage::Attachment.exists?(blob_id: record.blob_id, record_type: "Media::Asset", name: "file")`): the job bumps once for the library.

- [ ] **Step 1: Write the failing tests:**
  - `rendition_job_test.rb`: "an upload enqueues one job on the images queue and no TransformJob"; "the job makes every width of the image, records one generation under the current fingerprint and the page's srcset names them"; "a width carries no camera data" (rotated.jpg's 480 width has no `exif-data`, and is portrait); "an animated GIF's widths are animated WebP" (`n-pages` of the 480 file is 3); "a second run under the same settings makes nothing" (`ActiveStorage::VariantRecord.count` unchanged); "a change of settings keeps the previous generation's files and deletes the one before it" (three runs under three formats: the first generation's variant records gone, the second's kept); "a failure is retried and recorded by its class after the last attempt, and the image keeps its preview"; "an unreadable old row is recorded at once, not retried"; "regenerate, then a new format saved before the job ran: the image is made once, with the new format" (Review Focus 4: enqueue, change `image_format` to `avif` with `avif_available?` stubbed true or quality instead when the CI's libvips has no AV1, perform all; one generation, its fingerprint the newest); "the span carries the queue latency, each width's duration and the bytes, and no file name".
  - `job_queues_test.rb`: "every job of the app is on default or images, and images holds only the image jobs" (every `ApplicationJob` descendant's `queue_name`; Active Storage's analysis and transform queues are `images`, purge `default`); "the default worker does not take the images queue" (load `config/queue.yml` through ERB: no worker's queues is `"*"`, `images` has one thread).
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/jobs/media test/lib/job_queues_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the job, the queue configuration, the enqueue and the initializer's narrowing (rewrite its comment as the invariant: the library's widths bump once per generation, from the job). `test/support/media_renditions.rb#make_renditions!` now performs the job inline.
- [ ] **Step 4: Run** the two files, `test/jobs`, `test/models/media`, `test/lib/telemetry`, `test/lib/version_bump_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: an image's widths made by one job on a queue of its own`.

### Task 5: The content version moves only when a live page can show the image

**Files:**
- Modify: `app/models/media/usage.rb` (scope), `app/models/media/asset.rb` (the `after_commit`), `app/jobs/media/rendition_job.rb` (the bump), Create: `test/models/media/asset_version_test.rb`

**Interfaces:**
- Produces: `Media::Usage.shown_publicly` (scope: role `published`, or an owner `Page`/`Post` kept with `published_at` not nil, or a `ContentBlock` whose owner is such a page or post; Active Record `.or` as `by_kept_owner` is written); `Media::Asset#shown_publicly? -> Boolean` (`usages.shown_publicly.exists?`; on any `StandardError` logs the class and answers true). The asset's `after_commit { PublicSite.bump_version! if shown_publicly? }` carries the race comment of D4 ("No race loses a bump").

- [ ] **Step 1: Write the failing tests:** "an upload, its decode and its job move the version not at all while no page uses the image"; "an alt edit of an image only a draft uses moves nothing; of one a live page uses, once"; "a generation of an image a scheduled post's copy shows moves the version once, not once per width"; "an image a live page's block shows moves it, through the block"; "when the question raises the asset bumps" (stub `Media::Usage.shown_publicly` to raise); "publishing a page whose image is still being made, then the job: the version moved after both" (both orders, D4).
- [ ] **Step 2: Run** the file. Expected: FAIL (today every commit bumps).
- [ ] **Step 3: Implement** the scope and both bumps.
- [ ] **Step 4: Run** the file, `test/models/public_site`, `test/models/media`, `test/lib/version_bump_test.rb`, `test/integration/public_caching_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: an image moves the content version only when a live page can show it, and once per generation`.

### Task 6: What a page draws, and the fade

**Files:**
- Create: `app/javascript/controllers/image_fade_controller.js`, `app/assets/tailwind/themes/default/images.css` (imported from `theme.css`), `test/system/image_loading_test.rb`
- Modify: `app/components/media/picture_component.rb`, `.html.erb`, `app/sanitizers/rich_text_scrubber.rb`, `app/javascript/controllers/index.js` (`SITE_ONLY`), `app/javascript/site.js`, `test/components/media/picture_component_test.rb`, `test/models/rich_text/` (the scrubber's test), `test/values/theme/contract_test.rb` only if its rich-text assertion needs the new attributes named

**Interfaces:**
- Consumes: `Media::Asset#srcset`, `#src`, `#preview_data_url`, `#has_alpha`, `#width`, `#height` (Tasks 2–3).
- Produces: `Media::PictureComponent` draws one `<img>` in three states. Widths made: `src` = `asset.src`, `srcset`, `sizes`, `width`, `height`, `style` = `Media::PictureComponent.preview_style(data_url)` unless `has_alpha`, `data-controller="image-fade"`. No width: `src` = the preview, `width`, `height`, `data-image-preview` (the preview-only look, CSS). Neither: the `<img>` with no `src`, with `width`, `height`, `alt` and `data-image-empty`, styled `background: var(--th-sunken)` (an `<img>` with no `src` shows its sized box and its alt; never the original). `render?` stays `asset&.file&.attached?`.
- Produces: `Media::PictureComponent::PREVIEW_STYLE = /\Abackground:url\("data:image\/webp;base64,[A-Za-z0-9+\/=]+"\) center\/cover no-repeat\z/` and `.preview_style(data_url) -> String` matching it; `RichTextScrubber` keeps an `img`'s `style` only when it matches, keeps `src` that is a `data:image/webp;base64,` preview on `img` (confirm whether Loofah already allows it), and keeps `data-controller="image-fade"`, `data-image-preview`, `data-image-empty` on `img` only.
- Produces: `image_fade_controller.js`: on `connect`, if the image is not `complete`, set `data-image-loading` and remove it on `load` or `error`; on `turbo:before-cache` remove it; `disconnect` removes it and the listeners. No words. `images.css`: `img[data-image-loading]` takes the preview look (Ruling 2), `img[data-controller~="image-fade"]` has `transition: filter <duration>` (a placeholder value with a comment that the Design System's question 2 sets it), none under `@media (prefers-reduced-motion: reduce)`; `img[data-image-preview]` blurred and scaled to its box; `img[data-image-empty]` `background: var(--th-sunken)`.

- [ ] **Step 1: Write the failing tests:**
  - `picture_component_test.rb`: "with widths the img offers only them, the middle one as src, its size and its preview as background, and no address of the original"; "an image with alpha gets no background"; "with no width the src is the preview and the img carries its size"; "with neither the img is a sized box with its alt and no src"; "it is one img and nothing around it" (the rendered fragment's only element is `img`); "an image narrower than 480px offers its own width".
  - Scrubber test: "a rendered rich-text image keeps its preview style, its preview src and the fade's attribute"; "any other style on an img, and the fade's attribute on another element, are dropped"; and `test/values/theme/contract_test.rb`'s "a rendered text is the elements the contract lists, under no class of its own" still passes.
  - `test/system/image_loading_test.rb` (Cuprite; hold the width's response with a route that never answers, e.g. the image's URL pointed at a stalled `Rack` app through `page.driver.browser.network.intercept`, or the asset's widths made and the request intercepted): "an image still loading is marked and loses the mark when it has loaded"; "an image already in the browser's cache is never marked"; "under reduced motion the image has no transition" (emulate `prefers-reduced-motion: reduce` with `Emulation.setEmulatedMedia`, reset in an `ensure`); "Turbo's copy of the page holds no mark" (visit, follow a link, `page.go_back`, assert no `[data-image-loading]` before the controller connects, via the snapshot's HTML read in a `turbo:before-render` listener); "without the script the image appears" (the CSS hides nothing without the attribute: computed `filter` is `none` on an img without it). Every wait is `assert_eventually`/`await_js`; no `sleep`.
  - `test/integration/public_javascript_test.rb`: add "the image fade is registered by the site entry point and not by CS Studio's" (CS Studio's layout imports no path that registers `image_fade_controller`; read `index.js`'s `SITE_ONLY` and `site.js`).
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/components/media test/models/rich_text test/values/theme/contract_test.rb test/integration/public_javascript_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the component, the scrubber, the controller, the registration and the CSS; rewrite the component's comment for the three states and why there is no wrapper.
- [ ] **Step 4: Run** the step-2 files, then `bin/rails tailwindcss:build` and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/image_loading_test.rb test/system/theme_script_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/integration/theme_pages_test.rb test/values/theme test/lib/theme_css_test.rb test/lib/theming_reference_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: a page draws an image's widths over its preview, the preview until they exist, and fades it in`.

### Task 7: Proxy mode, the originals and the unmade variants

**Files:**
- Create: `app/controllers/concerns/active_storage_library_original_refusal.rb`, `app/controllers/concerns/active_storage_made_variants_only.rb`, `app/controllers/admin/media_originals_controller.rb`, `test/integration/image_delivery_test.rb`, `test/controllers/admin/media_originals_controller_test.rb`
- Modify: `config/application.rb` (`config.active_storage.resolve_model_to_route = :rails_storage_proxy`), `config/initializers/active_storage_access.rb`, `config/routes.rb` (`get "media/:id/original", to: "media_originals#show", as: :media_original` inside the admin scope), `app/components/admin/media_library/panel_component.*` ("Download original"), `config/locales/admin/media_library.en.yml` (create if the folder has none: follow `docs/reference/i18n.md`), `test/integration/admin/note_files_test.rb`

**Interfaces:**
- Produces: `ActiveStorageLibraryOriginalRefusal` (included in `Blobs::RedirectController`, `Blobs::ProxyController`, `DiskController`): `blob_scope` leaves out a blob attached as `Media::Asset#file` (`where.not(id: ActiveStorage::Attachment.where(record_type: "Media::Asset", name: "file").select(:blob_id))`), a 404; the disk controller's `show` answers 404 for a key whose blob is such a blob. A refusal carries no `Cache-Control: public`.
- Produces: `ActiveStorageMadeVariantsOnly` (included in both representation controllers): overrides `set_representation` (the base class's private `before_action`, which processes inline) and answers 404, before anything is processed, when the blob is a library file and `@blob.variant_records.where(variation_digest: ActiveStorage::Variation.decode(params[:variation_key]).digest)` is empty; other blobs (the logo) call `super`.
- Produces: `Admin::MediaOriginalsController#show`: `media.upload` gate as `Admin::MediaController`'s (403 without), a kept asset by id else 404, streams the blob (`ActiveStorage::Streaming#send_blob_stream`, `disposition: :attachment`) with `Cache-Control: private, no-store`. Route helper `admin_media_original_path(asset)` (whatever name the admin scope gives it; the panel uses it).

- [ ] **Step 1: Write the failing tests:**
  - `image_delivery_test.rb`: "a made width is answered public, for a hundred years, immutable, in one request" (GET the `srcset` URL of a made asset: 200, `Cache-Control` includes `public`, `immutable`, `max-age=3155695200`; no redirect); "a library original is refused by every read route, signed out and signed in" (blob proxy, blob redirect, the disk URL of its key: 404, no `public`); "an unmade width of a library image is a 404 and no variant is made" (`VariantRecord.count` unchanged; a variation key for 2,400 built by hand); "the logo is served through the proxy with the same headers, and its variants still bump" (render the public layout, find the logo's address, GET it).
  - `media_originals_controller_test.rb`: "an editor with media.upload downloads the original as an attachment, private and not stored"; "without media.upload it is the 403; a trashed or missing id the 404".
  - `note_files_test.rb`: add "a note's blob through every read route answers no public, cacheable answer" (blob proxy, blob redirect, representation proxy and redirect, disk).
  - The panel's component test: "the panel offers Download original to someone who may open it".
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/integration/image_delivery_test.rb test/controllers/admin/media_originals_controller_test.rb test/integration/admin/note_files_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the setting, the two concerns (in `to_prepare`, `include?`-guarded, as the note refusal is; the comment in `active_storage_access.rb` says which controller refuses what and why `set_representation` is overridden rather than followed), the controller, the route and the panel's link.
- [ ] **Step 4: Run** the step-2 files, `test/integration/admin/media_test.rb`, `test/integration/mcp_media_test.rb` (confirm the MCP answers hold no address: they hold none today) and `test/integration/public_caching_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: images at fixed public immutable addresses, the original for editors alone, and no request makes a width`.

### Task 8: CS Studio shows widths, previews or a box, never the original

**Files:**
- Modify: `app/components/admin/media_library/tile_component.*`, `panel_component.*` (`preview_url` → `display_url(min_width: 960)`), `grid_component.rb`, `app/components/admin/columns/media_column_component.*`, `app/components/admin/columns/rich_text_column_component.rb` (`url:` → `display_url(min_width: 960)`), `app/components/admin/editor_screen/tile_summary_component.*`, `app/components/admin/trash_screen/row_component.html.erb`, `app/controllers/concerns/admin/media_upload_responses.rb` (`url:` → `display_url(min_width: 960)`), `app/views/admin/media/index.html.erb` (the hint reads the setting's MB through a key), `app/javascript/controllers/admin/media/upload_controller.js` (its "over 10 MB" comment), their tests

**Interfaces:**
- Consumes: `Media::Asset#thumbnail_url`, `#display_url(min_width:)`, `#width`, `#height` (Task 3).
- Produces: every CS Studio `<img>` of a library image carries `width` and `height`; where `thumbnail_url`/`display_url` is nil the component draws a `bg-sunken` box (CS Studio's token) of the same size and no `<img>`; a preview `src` gets a class that blurs it (the look is question 4).

- [ ] **Step 1: Write the failing tests** in each component's test: "a tile of an image whose widths exist shows the 480 width with its size"; "a tile of an image with no width shows its preview, and one with neither a box; neither is the original" (assert no `/blobs/` path anywhere in the rendered HTML of the grid, the panel, the picker, the media field, the tile summary, the trash row and the upload answer); "the upload answer's url is a width or the preview".
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/components/admin test/integration/admin/media_test.rb test/integration/admin/media_assets_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the components and the answer.
- [ ] **Step 4: Run** the step-2 files, `test/lib/admin_design_rules_test.rb`, `test/lib/admin_i18n_test.rb`, then `bin/rails tailwindcss:build` and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/media_library_test.rb test/system/admin/media_picker_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: CS Studio shows an image's width, its preview or a box, never the original`.

### Task 9: Existing sites: the adopted widths, the backfill and the console task

**Files:**
- Create: `db/migrate/<ts>_adopt_existing_image_variants.rb`, `app/jobs/media/backfill_job.rb`, `test/migrations/adopt_existing_image_variants_test.rb` (follow the existing migration tests' place; `grep -rl "migration" test/lib test/migrations 2>/dev/null`), `test/jobs/media/backfill_job_test.rb`
- Modify: `config/recurring.yml` (`media_backfill`, class `Media::BackfillJob`, queue `images`, every 10 minutes, in production and development), `lib/tasks/media.rake` (`media:variants` becomes `media:regenerate`), `test/lib/built_in_data_test.rb`, `test/tasks/` (the rake task's test, if one exists)

**Interfaces:**
- Consumes: `Media::Generation`, `Media::Renditions`, `ImageSettings` (Tasks 1, 3); `Media::RenditionJob` (Task 4).
- Produces: the migration, for every asset with `VariantRecord`s of today's four transformations (`resize_to_limit: [w, nil], format: :webp`, rebuilt in the migration itself, not from the model, which no longer declares them): `renditions = { "current" => { fingerprint, files: [{width, key, digest}…] } }` and `renditions_fingerprint`, in one `update_columns` per asset with `# version: none (the same widths the page already named)`. The fingerprint: Ruling 11 (the default settings' when a GPS JPEG's old width has no `exif-data`, else `"adopted"`); `down` empties both columns.
- Produces: `Media::BackfillJob#perform`: enqueues `Media::RenditionJob` for each kept asset with `preview IS NULL OR width IS NULL`, `renditions_failed_at IS NULL`; nothing else.
- Produces: `bin/rails media:regenerate`: calls `Media::Regenerate` (Task 10) as `System`; until Task 10 exists, enqueues `Media::RenditionJob` for each kept asset not `made_with?` the current fingerprint and prints the count. Keeps the rule "look at what is made, never at what is queued".

- [ ] **Step 1: Write the failing tests:** migration: "an asset's four processed widths are adopted, and the page names the same addresses as before the migration" (build variant records with the old transformations, compare the old `rails_representation_path`'s variation key with the adopted key); "an asset with no processed width is left to the backfill"; "a GIF and an image narrower than 480px are adopted with nothing". `built_in_data_test.rb`: the new migration's entry `derived: "the widths images already had"` makes "every migration that inserts rows is accounted for…" pass (red first). Backfill: "an old row with no preview or size gets both from one job, and a row that cannot be decoded is recorded failed and asked again never". Rake: "media:regenerate enqueues the stale images once and nothing for a made one".
- [ ] **Step 2: Run** the files and `test/lib/built_in_data_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the migration (check camera data on one old width as Ruling 11 says, record which in the migration's comment), the job, the recurring entry and the task.
- [ ] **Step 4: Run** the step-2 files and `test/models/seeds_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: existing images keep their widths through the deploy and get their previews from a backfill`.

### Task 10: Settings → Images and Regenerate images

**Files:**
- Create: `app/services/media/regenerate.rb`, `app/queries/media/rendition_progress.rb`, `app/components/admin/settings_screen/images_card_component.{rb,html.erb}`, `test/services/media/regenerate_test.rb`, `test/queries/media/rendition_progress_test.rb`, `test/components/admin/settings_screen/images_card_component_test.rb`, `test/integration/admin/settings_images_test.rb`, `test/system/admin/settings_images_test.rb`
- Modify: `app/services/settings/save.rb` (`IMAGE_ATTRIBUTES`; AVIF refused when `ImageSettings.avif_available?` is false), `app/controllers/admin/settings_controller.rb` (permit the five fields; `regenerate_images`), `config/routes.rb` (`post :regenerate_images` in `resource :settings`), `app/views/admin/settings/show.html.erb` (the card for `settings.manage`), `config/locales/admin/settings_screen.en.yml`, `app/models/audit/sentence.rb` (`media.regenerated`), `app/models/editing/signals.rb` (`SILENT`: "regenerating images changes no content an editor has open"), `test/services/service_behaviour_contract_test.rb` (`EXPECTED_SERVICES`), `test/support/service_calls.rb` (factory), `test/integration/trash_visibility_test.rb`, `lib/tasks/media.rake` (call the service)

**Interfaces:**
- Consumes: `ImageSettings` (Task 1), `Media::RenditionJob` (Task 4), `renditions_fingerprint`/`renditions_failed_at` (Task 2).
- Produces: `Media::RenditionProgress.new(fingerprint: ImageSettings.current.fingerprint, scope: Media::Asset.kept).counts -> { total:, made:, failed: }` (one statement; `made` = fingerprint equal; `failed` = `renditions_failed_at` not nil and not made).
- Produces: `Media::Regenerate.new(actor:).call -> Result` (`authorize!("settings.manage", site)`; enqueues one `Media::RenditionJob` per kept asset not made with the current fingerprint or missing its preview or size; `record_event("media.regenerated", subject: site, metadata: { "count" => n })`; success with the count). Audit sentence "regenerated N images".
- Produces: `POST /cs-studio/settings/regenerate_images` → 303 to the settings screen's `#images`, with a toast naming the count; 403 without `settings.manage`.
- Produces: `Admin::SettingsScreen::ImagesCardComponent.new(site_setting:, values:, progress:, avif_available:)`: format (WebP / AVIF, AVIF disabled with its reason when unavailable, and the line that older browsers then show nothing), quality for each format, widths as one field of comma-separated numbers (the field's look is question 5), largest upload in MB, the count "N of M images made with these settings" and the failed count, and "Regenerate images…" outside the SaveBar's form, opening an `Admin::Ui::DialogComponent` that says how many images. All words are keys.

- [ ] **Step 1: Write the failing tests:**
  - `rendition_progress_test.rb`: "counts kept images only: made with these settings, failed, and all" (a trashed image is in none); one statement (`capture_sql`).
  - `regenerate_test.rb`: "it enqueues each stale or preview-less kept image once, audits the count, and touches no trashed image"; "a second press while the jobs are queued makes each image once" (perform all: one generation each); "without settings.manage it is denied".
  - `settings_images_test.rb` (integration): "an owner saves the four settings, audited as a settings change, and nothing is made until Regenerate"; "widths typed out of order are saved sorted; a width typed twice is refused with a sentence and nothing is saved" (Review Focus 3); "AVIF is refused when the server cannot write it"; "a quality of 0 and an upload of 51 MB are refused"; "uploads take the saved largest upload at once" (save 1 MB, upload 1.1 MB: refused with "1 MB"); "Regenerate images enqueues and answers 303 with the count; without settings.manage it is the 403".
  - `trash_visibility_test.rb`: "a trashed image is in no count of the Images card or of System status's Images row".
  - System test: "the Images card saves through the save bar, and Regenerate asks first, then says how many" (confirmation dialog, then the toast).
  - The service contract tests, `test/models/audit/sentence_test.rb` and `test/models/editing/signals_test.rb` ("every action the app records is mapped or silent") go red until the entries exist.
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/queries/media test/services/media test/integration/admin/settings_images_test.rb test/integration/trash_visibility_test.rb test/services/service_behaviour_contract_test.rb test/services/service_contract_test.rb test/models/editing/signals_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the query, the service, `Settings::Save`'s image attributes (under its existing `site.lock!`), the controller action, the route, the card and the keys.
- [ ] **Step 4: Run** the step-2 files, `test/components/admin/settings_screen`, `test/integration/admin/settings_test.rb`, `test/lib/admin_i18n_test.rb`, `test/lib/admin_design_rules_test.rb`, then `bin/rails tailwindcss:build` and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/settings_images_test.rb test/system/admin/settings_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Settings → Images, and Regenerate images with its progress`.

### Task 11: System status's Images row

**Files:**
- Modify: `app/models/setup/system_check.rb` (an `images` row after `image_processing`; the `image_processing` warning's wording; constructor takes `image_progress:` so the model names no query it cannot be handed, defaulting to `Media::RenditionProgress`), `app/controllers/admin/system_status_controller.rb` (the link for `settings.manage`, as the Mail row's), `test/models/setup/system_check_test.rb`, `test/integration/admin/system_status_test.rb`

**Interfaces:**
- Consumes: `Media::RenditionProgress#counts` (Task 10).
- Produces: row label "Images": ok "Every image is made with the current settings." when `made == total`; warning "N of M images still to be made." when some are not made and none failed; warning "N images could not be made." when any failed (both sentences when both); `link: :image_settings` for a holder of `settings.manage`. "Image processing"'s warning ends "…so images can't be made and pages show their previews." instead of naming variants.

- [ ] **Step 1: Write the failing tests:** system check: "the Images row is OK when every kept image is made with the current settings, and warns with the counts otherwise"; "a failed image is counted as could not be made"; "the Image processing warning says pages show previews and no longer names the original". Integration: "the Images row links to Settings → Images for settings.manage and to nothing otherwise".
- [ ] **Step 2: Run** `PGGSSENCMODE=disable bin/rails test test/models/setup/system_check_test.rb test/integration/admin/system_status_test.rb`. Expected: FAIL.
- [ ] **Step 3: Implement** the row and the link.
- [ ] **Step 4: Run** the step-2 files and `test/integration/trash_visibility_test.rb`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: System status says how many images are still to be made`.

### Task 12: Measure, the reference, the rules and the guide list

**Files:**
- Modify: `docs/reference/media.md` (rewrite "The asset" for the decode, the preview, the generation, the job and its queue, the three states, the fade; the new section "Delivery": proxy mode, headers, the two refusals, Download original, the content version rule; "In tests": `make_renditions!`; the measured figures; the interim line "until a variant has been processed, a page serves the original" removed), `docs/reference/hosting.md` (the `images` worker, `JOB_CONCURRENCY` and `SOLID_QUEUE_IN_PUMA` for images, the request limits of Thruster and kamal-proxy against 50 MB, that a CDN is optional, needs no setting and caches images by their headers, whether Thruster's cache or `X-Sendfile` is worth turning on; and the wrong line at `:167` the review names), `docs/reference/theming.md` (what `Media::PictureComponent` draws now, the attributes, `--th-sunken`, the release note; the lines at `:770` and `:800`), `docs/reference/rich-text.md` (the scrubber's preview rule; the variant bump paragraph), `docs/reference/settings-languages-ai.md` (the Images card), `docs/roadmap.md` (the three rows, C2, the known gap and the demo row to "Shipped"/removed; the lines at `:14` and `:176`), `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Measure** on the documentation site's server (Ruling 13 if unreachable): a page's time to the hero's paint and its bytes on a throttled phone profile before and after, the upload's time with the decode and preview for a 10 MB image, one generation's time per image (WebP and an animated GIF). Write the figures into `media.md`.
- [ ] **Step 2: Write `CLAUDE.md`'s rules**, short, each naming its test FILE (no quoted test names, spec's "Shrink CLAUDE.md" part): no public route, page, srcset or MCP answer gives a library original, and no request makes a variant (`test/integration/image_delivery_test.rb`); an image moves the content version only when `Media::Usage.shown_publicly` holds, and the library's widths once per generation from `Media::RenditionJob` (`test/models/media/asset_version_test.rb`); an asset's `width`, `height` and preview come from `Media::Decoding` at validation on every path that makes one (`test/models/media/asset_test.rb`); image jobs are on `images`, everything else on `default` (`test/lib/job_queues_test.rb`); `Media::PictureComponent` stays one `<img>` and the scrubber keeps only its preview style (`test/components/media/picture_component_test.rb`). Update the media index line's file list (`app/jobs/media/`, `app/values/media/`, `app/queries/media/`, the two concerns, `Admin::MediaOriginalsController`).
- [ ] **Step 3: Run** `PGGSSENCMODE=disable bin/rails test test/lib`. Expected: PASS (the guards that read `CLAUDE.md` and `docs/reference`, `source_layout_test.rb` for every identifier written).
- [ ] **Step 4: Run the whole suite once** on a quiet machine: `PGGSSENCMODE=disable bin/rails test`, then `bin/rails tailwindcss:build` and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system`, then `bin/rubocop` and `bin/brakeman`. Expected: all green, brakeman exit 0.
- [ ] **Step 5: Commit** `docs: image delivery in the reference, the rules and the roadmap`.
- [ ] **Step 6: Write the PR's "Documentation" section** (in the report to the controller, not a file): the guide pages of the spec's "Documentation" list (`docs/editors/media/the-media-library.md`, `docs/editors/pages/the-rich-text-editor.md`, `docs/administrators/site/site-settings.md`, `docs/administrators/operations/system-status.md`, `docs/administrators/operations/maintenance-commands.md` (`media:regenerate`), `docs/administrators/install/what-contentspiel-asks-of-its-host.md`, `before-you-go-live.md`, `a-first-deploy-step-by-step.md`, `install-and-first-start.md` (line 48), `docs/integrators/how-it-works/urls-languages-and-caching.md`, `docs/integrators/theming/rendering-blocks-and-pages.md`, `the-theme-contract.md`, `what-a-theme-cannot-do.md`; `the-mcp-server.md` needs nothing, its tools answer no address), plus the release note for the `<img>`'s new attributes and the eight Design System questions still open.

## Order

1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12. Task 9's `media:regenerate` calls the service once Task 10 exists (Task 10 edits the rake file).
