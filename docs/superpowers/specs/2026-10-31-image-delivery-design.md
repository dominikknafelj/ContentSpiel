# Image delivery

Status: design, not built. The owner's decisions are of 2026-10-31 and are binding; they are marked "(owner)". The owner answered this spec's first questions the same day ("Owner's answers", 2026-10-31), folded in below as "(owner)". Calls marked "(controller's call)" are the coordinating reviewer's; calls marked "(my call)" are this spec's; both can be overturned at review. The looks are not decided here: they are questions for the Design System, listed at the end.

Roadmap rows this spec answers: "Image delivery", "Images in Settings" and "Image loading state" (all Should, owner, 2026-10-31), C2 under "Performance and caching" ("library images served in Active Storage proxy mode with long-lived headers"), the Media known gap "Until a variant has been processed, a page serves the original file at full size", and the demo-site row "On first load the tiles are grey for seconds while thumbnails are generated". The architecture review of 2026-10-31 (main `7420fa22`) found the causes at code level; which of its 35 findings this work closes, pulls a part of, or leaves is the table in "The architecture review's findings".

## Intent

An image on any ContentSpiel site shows at once and never moves the text, on a phone as on a desktop. In the terms of Core Web Vitals: an image never adds to the layout shift (CLS), and the largest image of a page (usually the hero) is not what holds the Largest Contentful Paint back.

The first case is the documentation site, whose screenshots take seconds to appear. The next is the owner's agency site, and after it every client site: whatever is decided here is what a stranger's site does on its first day, with nothing configured and no CDN.

## Why it is slow today

Verified on `main` (`47fd357f`) for this spec; the line numbers are of that commit.

1. **A page serves the original until the variants' jobs have run.** `Media::Asset` declares four named WebP variants (`VARIANT_WIDTHS`, `w480`/`w960`/`w1600`/`w2400`, `app/models/media/asset.rb:35` and the `has_one_attached` block) with `preprocessed:`, so `ActiveStorage::Attachment#transform_variants_later` enqueues one `ActiveStorage::TransformJob` per width after the upload commits. `#srcset` lists only variants with a finished `VariantRecord`, and `#src` (the `<img src>`) is always the original (`#url`, `rails_blob_path`). Until the jobs run, a phone gets the original, up to 10 MB and, on the documentation site, a 2,880px PNG. Once variants exist the original is still appended as the widest `srcset` candidate (`Media::PictureComponent#srcset_attribute`), so a wide screen with a high pixel ratio can still pick it. An image narrower than 480px gets no variant at all (a width at or above the original's is skipped) and is served as the original for ever. CS Studio's tiles do the same (`#thumbnail_url` falls back to the original), which is the demo site's "grey for seconds".
2. **The jobs wait behind everything else, and everything else waits behind them.** `config/queue.yml` has one worker on `"*"` with 3 threads; production runs it inside Puma (`SOLID_QUEUE_IN_PUMA: true`, `config/deploy.yml`); nothing sets `config.active_storage.queues`, so transforms and analysis are on `default` with mail delivery (`MailDeliveryJob`), the sweeps and the go-live job. A batch of 50 uploads is 200 transforms ahead of a password-reset mail.
3. **Every image is two Rails requests and nothing can keep it.** Nothing in `config/` sets `resolve_model_to_route` or `service_urls_expire_in`, so Active Storage 8.1 runs in redirect mode: `/rails/active_storage/blobs/redirect/…` and `/representations/redirect/…` answer a 302 with `Cache-Control: max-age=300, private` to a signed Disk URL that is minted again on every redirect. A browser revalidates after five minutes, Thruster (`Dockerfile`) and a CDN cannot store a private answer, and the image's own bytes are served by a second request through Rails.
4. **Each image change empties every render cache.** `Media::Asset` bumps the public content version on every commit, "used or not" (`after_commit { PublicSite.bump_version! }`, with a comment saying a usage lookup would cost more than the bump); `Media::Upload#analyze_dimensions` bumps again; and every `ActiveStorage::VariantRecord` commit bumps (`config/initializers/public_site_version.rb`). One upload moves the version about six times, and the version is in the rich-text render cache's key (`RichText::Document#render_cache_key`) and in the public ETag (`PagesController#show`). So an editor uploading a folder of images that no page shows yet makes every visitor's next view of every page a full render.
5. **Width and height can be missing.** `Media::Upload#analyze_dimensions` runs after the commit and only warns on failure, leaving `width`/`height` nil; `Media::PictureComponent` then omits the attributes and the image moves the text when it arrives.

## Goals

- An image never moves the text: every library image on a public page and in CS Studio carries its `width` and `height`.
- Until a real width exists, a page shows the blurred preview, never the original (owner). Once the widths exist, a page offers only them. The original never reaches the public at all (owner): the public gets only re-encoded widths, with camera data (EXIF, GPS, maker notes) dropped; signed-in editors can download the original from the media panel (decision 2).
- The browser keeps an image: a public, long-lived, immutable answer at an address that never changes for those bytes, so a second page view and a second visitor behind the same cache fetch nothing.
- A CDN in front can keep it too, with no CMS setting and no CDN named anywhere (owner).
- Mail and the site's own jobs never wait behind images.
- An image change that no public page shows moves the content version not at all; the widths of one image move it once.
- An owner can choose the format, quality, widths and largest upload, and make every image again at the current settings, seeing the progress.

## Non-goals

- Cropping, focal points, art direction (`<picture>` with different crops), video (owner: out of scope).
- The site logo's move into the library (its own roadmap row); the logo only gains the cacheable addresses here, through the global proxy mode (decision 2).
- A whole-page cache (C1), a shared lifetime for proxies (C7), purging a CDN (C4): the roadmap's caching sub-project. This spec makes images cacheable; pages stay `max-age=0, must-revalidate`.
- Re-keying the rich-text render cache on what it reads (the review's direction for "Every image change and publish empties every render cache"): this spec only removes the image bumps that should never have been.
- A schema field type for images (`:media`, the review's finding): not built, but nothing here may assume the three places an image is referenced today (decision 6).

## Anti-goals

- **Nothing depends on a CDN** (owner). Cloudflare, or any other, is optional. No setting names one, no header is vendor-specific, no URL is a CDN's, and a site with nothing in front is as fast as standard HTTP caching allows.
- **No request makes a variant.** A visitor's request never runs a transform, not for a missing width, not for a URL typed by hand (decision 2). A transform on a request thread is a Puma thread gone for a second on a small host.
- **No page waits for a width.** Only the preview is made while the upload waits (owner); a page never blocks on, or fails over, a width that is missing, slow or failed.
- **No wrapper element around the image** (my call). A theme's CSS styles `img` (`docs/reference/theming.md`, the rich-text table, "`img` | its picture"; `figure > img` in templates), so the image stays one `<img>`, with no `<picture>`, `<div>` or `<span>` around it and no class added inside rendered rich text (the contract's "a rendered text is the elements the contract lists, under no class of its own").
- **An image is never hidden by CSS alone.** If the page's script does not run, the image still appears when it has loaded, over its preview, with no fade.

## Decisions

### 1. The preview is made at upload, and the upload waits for it (owner)

At upload `Media::Upload` decodes the image once, after the blob is stored, and from that one decode takes the image's `width` and `height` and makes the preview: a version about 24px wide (owner), kept small enough to inline in every page that shows the image.

- **Stored on the asset's row, not as a variant** (my call). A variant is a file with an address, so inlining it would need a read from the storage service on every render. The preview is a few hundred bytes; it is a column of `media_assets` (name left to the builder) holding the encoded preview, written with `update_columns` in the upload's own request and read with the row, so a page that already loads the asset (`PublicPageRendering#preload_page_images`, `Media::Asset.with_variants`) pays nothing more.
- **Its format** (my call): WebP, every browser this site supports decodes it; how blurred and how many pixels is a Design System question, but the pixels are made by the server, so a blur done in the image (rather than by a CSS `filter`, which bleeds at the edges and costs paint) is the builder's choice to make with the Design System's answer.
- **`width` and `height` are an upload validation on every path that makes an asset** (controller's call): `Media::Upload` and `RichText::HtmlImport#create_asset` (which decodes inline today) both take them from the decode, before the asset is kept. A file that passes the byte sniff but cannot be decoded is refused with a sentence ("This file can't be read as an image", an i18n key), rather than kept as an image that could only ever be a box with no size. Today such a file is kept with nil dimensions and a log line; that is the CLS bug. Rows from before this change with no dimensions get them from the backfill job (decision 5); one that cannot be decoded there is drawn as the `th-sunken` box and listed on System status (decision 8). No `NOT NULL` constraint in this work: the old rows must be backfilled first, and the validation holds the new ones.
- **GIF** (owner): an animated GIF becomes an animated WebP at each width, like any image (all frames kept), and its preview is its first frame. The original GIF is never served publicly. The global rule "GIFs get no variants" (`#variable_image?`, the `preprocessed:` proc) goes; an animated width costs more CPU than a still one, which the builder measures and `media.md` records.
- The upload request takes longer by one decode and one tiny encode. For a 10 MB image with libvips that is well under a second; the builder measures it on the documentation site's server and records the figure in `docs/reference/media.md`.

### 2. Images are served in proxy mode at fixed addresses with long-lived public headers (owner: standard HTTP caching; the review's direction; roadmap C2)

`config.active_storage.resolve_model_to_route = :rails_storage_proxy`, globally (my call: the logo and every other public image become cacheable with it, and no code has to remember which helper to call). Active Storage's proxy controllers answer `http_cache_forever(public: true)`; the builder confirms what 8.1's version of that writes (`max-age` of a hundred years, `public`, and whether `immutable` is among them) and adds `immutable` if it is not, because the promise is honest:

- **An address names its bytes for ever.** A blob's signed id carries no expiry; a variant's address is the blob's signed id plus its variation key, and the variation key is a digest of the transformation (width, format, quality). The file of an asset never changes after upload (replacing it is a new blob, so a new address); a new format or quality is a new variation, so a new address. So nothing ever needs to be purged from a browser or a CDN: a change is always a new URL in the page.
- **Note files stay refused.** `config/initializers/active_storage_access.rb` already includes `ActiveStorageNoteFilesRefusal` in both proxy controllers, and `test/integration/admin/note_files_test.rb` ("Active Storage's public routes refuse a note's blob, by signed id and by a disk key, and still serve a library image") already requests the blob and representation proxy routes. This spec adds to the proof, not to the mechanism: a test that a note's blob through every read route answers no public, cacheable answer (the refusal's status and no `Cache-Control: public`), and that a library image's answer through the proxy is public and long-lived. CLAUDE.md's rule that no `rails_blob_path`, `url_for(blob)` or signed id of a note file is ever rendered is unchanged, and matters more under proxy mode: a rendered proxy URL of a note file would be refused, but must still never be written.
- **The original is the editors' alone** (owner). The blob proxy (and the blob redirect route, and the Disk route behind it) refuses a library asset's original to anyone not signed in to CS Studio, by a concern beside the note-file refusal: a library blob is recognised by its attachment to a `Media::Asset`, and the answer to a signed-in editor is `private`, never `public`, so no cache in front keeps it. The media panel offers "Download original" to someone who may open it (`media.upload`), through that route or a controller of CS Studio's own (the builder's choice; a CS Studio controller is the cleaner gate). A re-encoded width drops camera data (libvips' strip on save), so a phone photo's location never reaches the public. The logo stays a public original (it is not a library asset). Tests: a signed-out request for a library original by every read route is refused and not cacheable; a signed-in editor's is served `private`.
- **No request makes a variant** (my call, anti-goal). `ActiveStorage::Representations::ProxyController` calls `processed` on the representation, which transforms inline when the variant is missing. A page never links a missing width (decision 3), but the variation keys of the configured widths are predictable once one is seen, so a request for a width not made yet would run a 2,400px transform on a Puma thread. A concern beside the note-file refusal makes the representation controllers answer 404 for a variant with no `VariantRecord`, for library images (the logo's variants keep Rails' behaviour; it is one image, made at its save).
- **Rails still serves every image.** Proxy mode is one Rails request per image instead of two, streamed by a Puma thread. Thruster's own cache keeps public answers up to its item limit (1 MB by default), and the browser keeps everything, so a repeat view costs nothing. Whether a site needs more (Thruster's `X-Sendfile`, a larger cache, a CDN) is for the builder to measure and `docs/reference/hosting.md` to say; the CMS does not depend on it.

### 3. What a page shows: the preview until the image's widths exist, then only the widths (owner)

`Media::PictureComponent` stays the one place every image's tag is built, and stays one `<img>` (anti-goal). It has two states.

- **Widths exist** (the normal state): `src` is the middle width (my call: the one a browser without `srcset` support is best served by; the builder picks), `srcset` lists every made width, `sizes` as today, `width` and `height` always, and the preview inlined as the image's own background (my call: an inline `style` with a `data:` URL, which the public content security policy allows today: it sets no `style-src` or `img-src`, `config/initializers/content_security_policy.rb`). The image paints over its own preview as it loads. **The original is no longer a candidate** (owner): the widths made are every configured width below the original's width plus one at the original's own width capped at the largest configured width (decision 5), so the widest candidate is a re-encoded file of the original's size, not the original. This also gives an image narrower than 480px a WebP of its own, which today it never gets.
- **No width yet** (just uploaded, a failed generation, an image from before this change until it is made again): `src` is the preview itself, with `width` and `height`, and the image is blurred and scaled to its box. It is never the original (owner). Its look is a Design System question.
- **No preview either** (an image from before this change whose preview has not been made, or one whose preview failed): a quiet `th-sunken` box (owner), which is the token `--th-sunken` (`tokens.css`); the theme's value, so a theme with another sunken colour gets its own.
- **The fade** (owner: option C): a script marks an image that is still loading when it connects and lets it fade in over its preview when it has loaded; an image that was already loaded (cached) is left alone, and the attribute the script uses is taken back at `turbo:before-cache` as `code-copy` does (CLAUDE.md, Code block rule), so Turbo's snapshot never holds a half-faded image. Under `prefers-reduced-motion: reduce` there is no fade: the image appears at once (owner: "my call", the coordinator's). The script is registered by the public `site` entry point only, never CS Studio's (CS Studio's tiles use the same component but need no fade, my call), and holds no words. Without the script the image simply appears.
- **Inside rich text**: `RichText::ImageComponent` draws through the component, so the render cache holds the state the image was in when it was rendered. That is why a generation's completion moves the content version (decision 4): the next render holds the widths. No class is added (contract); attributes only.
- **CS Studio uses the same rule** (my call): a tile, the panel, the picker and an editor's image field show the smallest made width that covers the tile, else the preview, else the sunken box, never the original. `Media::Asset#thumbnail_url`'s fallback to the original goes. The grey tiles of the demo site become blurred previews from the first second.

### 4. The content version moves for an image only when a public page could show it, and once per generation (the review, pulled in)

- **An asset's own commit bumps only when a live record uses it** (the review's direction, my call on the predicate). The usage rows exist now (`Media::Usage`, `Media::UsageIndex`), so the comment's cost argument no longer holds: a bump is due when a usage row of the asset has an owner (through its block, for a block's row) that is kept and published or scheduled, or is a row of role `published` (the image a copy shows). One indexed query on `media_usages` joined to its owners, asked in the commit hook. When the question cannot be answered (an error), it bumps: a needless bump costs cache, a missing one shows a stale alt to visitors. A draft-only image needs none: the CS Studio preview is drawn every time (`RichText::Document`'s preview path) and no public page draws a draft.
- So an upload (unused at that moment), its analysis, an alt or title edit of an image nothing live shows, its trash and its purge (both refused while a kept record uses it) move nothing. `Media::Upload#analyze_dimensions`' own `PublicSite.bump_version!` goes with the analysis' move into the upload (decision 1).
- **A generation moves it once.** The library's variant records no longer bump one by one: the job that makes an asset's widths (decision 5) writes them, records the finished generation on the asset, and bumps once at the end, under the same "used by a live record" rule. `config/initializers/public_site_version.rb` keeps bumping for variant records of every other attachment (the logo), which are rare.
- **No race loses a bump** (my reasoning, to be kept in the code's comment): if an editor publishes a page with an image whose widths are still being made, either the generation commits first, and the publish's own bump makes the next render hold the widths, or the publish commits first, and the generation's check then sees the live use and bumps. Both orders end with a bump after both commits.
- Every write here around the callbacks (`update_columns` for the preview, the dimensions and the generation) carries its `# version:` line as `test/lib/version_bump_test.rb` asks, and the conditional bump says so on its line.

### 5. The widths are made in the background, on a queue of their own (owner; the review)

- **One job per image** (my call), not Active Storage's one `TransformJob` per named variant: it makes the image's widths smallest first, in one process and one download of the original, and ends with one record and one bump (decision 4). The `has_one_attached` block's `preprocessed:` variants go, because the widths come from Settings at run time (decision 7), and named variants are fixed when the class loads.
- **The generation is recorded on the asset** (my call). A column of `media_assets` holds the settings' fingerprint the widths were made under and, per width, what the page needs to name it (its width and its variation digest), written when the job has made every width. `#srcset` reads that column: it no longer reads `variant_records`, so `VARIANT_INCLUDES` and the three-association preload every list must remember become unnecessary (the builder removes them or keeps them for the logo). A page switches from one generation to the next only when the next is complete: a change of format in Settings never sends a page back to blurred previews while the regeneration runs.
- **The previous generation's files are kept until the next switch** (my call). A page rendered a moment before the switch, in a browser or a cache, still names them; they are deleted when the generation after the current one completes, by the job. Today's page lifetime is 0, so one generation is plenty; C7 must revisit this when pages get a shared lifetime.
- **The queue** (the review): the job, Active Storage's analysis and the logo's transforms are on a queue of their own (`images`, my name; `config.active_storage.queues.analysis` and `.transform` set to it), and `config/queue.yml` gets a second worker entry: `default` keeps its worker as today, `images` gets its own with ONE thread (my call: a batch of uploads must not take every core of a one-box host away from Puma), so mail is never behind an image and an image is never behind a sweep. Inside Puma (`SOLID_QUEUE_IN_PUMA`) as today; a host that runs `bin/jobs` separately gets both workers there.
- **Its polling** (my call, see the review's "Solid Cable polls" finding): a second worker is a second poll every second on an idle site. The `images` worker polls at a longer interval (2 s, the builder may choose another), since the preview covers the wait; the `default` worker is not changed here.
- **Existing sites need no owner action** (controller's call). A migration adopts an asset's existing `VariantRecord`s of today's four WebP widths into the generation column under the fingerprint of the default settings (derived from rows that were there, so it is named in `test/lib/built_in_data_test.rb` with `derived:` and its reason), so a page keeps its widths through the deploy. The missing previews, and missing dimensions, are made by a job queued once after the deploy (on the `images` queue, idempotent: it skips an asset that has them), so no image is a box for longer than that job takes. Today's originals that were served as the widest candidate are no longer offered; the adopted generation lacks the original's-own-width file and the narrow images' single width, which the next Regenerate makes (my call: adopting what exists beats remaking every image at deploy).
- **A failure** is recorded on the asset (when and the error's class, never a message that could hold a path), retried a few times by the job, and counted on System status (decision 8). A failed image keeps its preview on the page; never the original.
- **Telemetry** (the review: "if cheap"; it is): the job's span is a consumer root and is kept (`Telemetry::WorkSampler`); it carries the queue latency (enqueued to started), the duration of each width and the bytes in and out, as attributes with no file name and no path.

### 6. Where an image is used stays one derived place

Decision 4 asks `Media::UsageIndex`'s rows, never the three columns that reference an image today (`pages.hero_media_asset_id`, `content_blocks.media_asset_id`, a rich-text `image` node). So the day a `:media` field type feeds `Media::UsageIndex` (the review's finding), images in a gallery are bumped for correctly with no change here. This is the one part of that finding this work takes: not to make it harder.

### 7. Settings → Images (owner)

An "Images" card for owners (`settings.manage`), saved explicitly through `Admin::Ui::SaveBarComponent` like every configuration screen (CLAUDE.md), written by `Settings::Save` under its lock of the settings row, audited as a settings change.

- **Format** (owner): WebP by default; AVIF is an opt-in, with a line on the card that older browsers then show nothing. One `<img>`, no `<picture>`. AVIF is offered only when the server's libvips can write it (a probe like `Setup::SystemCheck`'s image probe), else shown with the reason it cannot be chosen; AVIF is several times slower to make than WebP, which the card may say too (wording to the Design System).
- **Quality**: one number per format (my call: 1–100, the encoder's own scale), default what libvips uses today, so a site that changes nothing gets the images it has.
- **Widths made**: today's 480, 960, 1600, 2400 by default. Bounds (my call): between one and six widths, each between 160 and 4,000, distinct; the card says what a width is for in a sentence the Design System writes.
- **Largest upload**: today's 10 MB by default. Bounded above (my call: 50 MB) because the upload decodes the whole image while it waits (decision 1), and libvips' memory follows the pixels; the builder also checks the request limits in front (Thruster, kamal-proxy) and says them in `hosting.md`. `Media::Asset::MAX_BYTE_SIZE` becomes the default of the setting, and every place that says "10 MB" (the refusal's sentence, the upload hint, the guide) reads the setting.
- **Saving changes nothing until "Regenerate images" is pressed** (owner). The saved settings are the ones Regenerate makes images with; until then pages keep each image's generation, and the card says how many images use old settings. New uploads take the saved settings (my call: the card's count then says honestly that the others are old; an upload made with settings the owner has not regenerated under is what the owner asked for by saving).
- **"Regenerate images"** (owner): a button on the card, outside the SaveBar's form (it is an action, not a field), behind a confirmation dialog that says how many images and roughly what it costs. It enqueues one job per kept image whose generation's fingerprint is not the current settings' (and makes the preview of an image that has none, and its dimensions when missing: this is also how the images from before this change get theirs). Progress is derived, never counted (my call, as mail's state is derived from its fingerprint): "N of M images made with these settings", read from the assets' recorded fingerprints on every view, so a restart, a lost job or a second press can never make the count wrong. It is audited (an action of its own, placed in `Editing::Signals::SILENT` with its reason, as every action must be). A second press while jobs are queued enqueues nothing twice (the job is idempotent per image and fingerprint).
- **Trashed images** (my call): the counts are of kept images (CLAUDE.md: trashed images are hidden explicitly at each narrowing point; the count belongs in `test/integration/trash_visibility_test.rb`). A trashed image is made again when it is restored, if its generation is stale.
- `bin/rails media:variants` becomes "the same as the button, from a console" and keeps its name or is renamed by the builder; its idempotence rule (look at what is made, never at what is queued) stays.

### 8. System status (owner)

A row "Images" beside "Image processing": OK when every kept image is made with the current settings; a warning while some are still to be made ("N of M images still to be made"), when some failed ("N images could not be made"), or when an old image could not be decoded at backfill (counted with the failed; it is drawn as the `th-sunken` box), linking to Settings → Images for a holder of `settings.manage` (as the Mail row links). The "Image processing" row's warning stops saying that "pages serve the original, full-size file" (the guide says so today): they serve previews.

## Constraints from CLAUDE.md this touches

- **The content version**: moves only through `PublicSite.bump_version!`; every write around the callbacks bumps or says `# version: none (reason)` (`test/lib/version_bump_test.rb`). Decision 4 changes when an image bumps, not how.
- **Trashed images** are hidden at each narrowing point; the Images card's counts and System status's row are new counts over images and join `test/integration/trash_visibility_test.rb`.
- **Note files** are never served by Active Storage's public routes, proxy included, and no URL of one is ever rendered (decision 2).
- **The theme contract**: `Media::PictureComponent` is called by templates and is not replaceable (`theming.md`, "So the replaceable components are…"); what its tag carries is not on a list, but `theming.md` says a change to a call a scaffolded template makes is said in the release notes "like a contract change". The new attributes on the `<img>` (the preview's background, the fade's attribute) are such a change: no element is added or removed, `img` stays the selector. Whether a theme may restyle the loading state, and so whether its attribute becomes a contract name with a ledger line, is question 6.
- **Rich text**: a rendered text stays the elements the contract lists, under no class of its own (`test/values/theme/contract_test.rb`); a theme does not change rich text's HTML, and the render cache stays keyed as it is.
- **i18n**: every string of the Images card, the dialog, System status's row (as its neighbours are written: the builder follows `docs/reference/i18n.md` for that screen) and the new upload refusal are keys under `config/locales/admin/`; the public site gains no words.
- **Design tokens**: CS Studio's card uses tokens, no literals (`test/lib/admin_design_rules_test.rb`); the public fallback is `--th-sunken`, a theme token.
- **Services**: `Settings::Save` writes the settings and the regenerate action is an `ApplicationService` that calls `authorize!(` and `record_event(`, with its entry in `EXPECTED_SERVICES` and a factory (`test/services/service_behaviour_contract_test.rb`). The job's writes of the preview, the generation and the failure are not content and not an `ApplicationService` (like mail's state columns): they are `update_columns` with their `# version:` line, never a save of the asset.
- **New columns** of `site_settings` and `media_assets` are placed in `Audit::Snapshot`'s lists (the fingerprint, the preview and the generation are never in a snapshot: they are derived), and a new database gets them from `db/schema.rb`; the migration that adopts existing variants writes rows derived from rows that were there, and is named in `test/lib/built_in_data_test.rb` with `derived:` (decision 5).
- **Import maps**: the fade's script is a top-level controller of the `site` entry point; no new pin, nothing preloaded on CS Studio for it.
- **No fixed sleeps** in its system tests; a test of the fade emulates `prefers-reduced-motion` and resets it in an `ensure`, as a font-size test does.

## Left to the builder

- Measure first, on the documentation site, and write the figures into `docs/reference/media.md`: a page's time to the hero's paint and its bytes on a throttled phone profile, before and after; the upload's time with the preview; a generation's time per image. The roadmap row's "Measure first" stands; the target is the intent, not a number.
- The names of the columns, the queue, the job and the concern; the fingerprint's shape (mail's HMAC-of-the-settings pattern is the model).
- The middle width for `src`; the exact predicate's SQL for "a live record uses it" (Active Record, then Arel, through a named scope); how the fade's attribute is set and taken back.
- Whether Thruster's cache and `X-Sendfile` are worth turning on by default for a one-box host, and what `hosting.md` says of a CDN (that it can sit in front, needs no setting, and caches images because of their headers).
- The logo: confirm it is served through the proxy routes with the same headers and that its variants still bump.
- MCP's `get_media_tool` and `list_media_tool` answer image addresses: confirm they become the proxy's and say nothing of the original that a page no longer shows.

## Documentation

Guide pages this changes (in `~/src/contentspiel-docs`), updated before release:

- `docs/editors/media/the-media-library.md`: "Download original" in the panel, and that the site shows only re-encoded copies without camera data; GIFs stay animated; the largest upload follows Settings; tiles show a blurred preview until the widths are made; a file that cannot be read as an image is refused.
- `docs/editors/pages/the-rich-text-editor.md`: what an image looks like right after upload.
- `docs/administrators/site/site-settings.md`: the Images card, its four settings and Regenerate images.
- `docs/administrators/operations/system-status.md`: the new Images row; the Image processing row no longer says pages serve the original.
- `docs/administrators/operations/maintenance-commands.md`: `media:variants`, as it becomes.
- `docs/administrators/install/what-contentspiel-asks-of-its-host.md`, `before-you-go-live.md`, `a-first-deploy-step-by-step.md`: the second worker and its queue, `JOB_CONCURRENCY` and `SOLID_QUEUE_IN_PUMA` for images, the request limits in front, and that a CDN is optional and needs no setting.
- `docs/administrators/install/install-and-first-start.md`: its line 48 ("There is no published CMS image (gap T-02)") is corrected in the same pass (the review's finding, below).
- `docs/integrators/how-it-works/urls-languages-and-caching.md`: images' addresses and headers, and when an image moves the content version.
- `docs/integrators/theming/rendering-blocks-and-pages.md`, `the-theme-contract.md`, `what-a-theme-cannot-do.md`: what `Media::PictureComponent` draws now (the preview, the attributes), with the release note.
- `docs/integrators/how-it-works/the-mcp-server.md`, if the media tools' addresses change shape.
- The documentation site's own config: it sits behind Cloudflare Access, which is that site's matter, not the CMS's; its owner decides whether Access is to let cacheable images through.

## The architecture review's findings

The review of 2026-10-31 (main `7420fa22`) has 35 findings. The owner's rule: a finding about code this work changes has its part pulled into this work. The files this design changes: `app/models/media/asset.rb`, `app/services/media/upload.rb`, `app/components/media/picture_component.*`, `RichText::ImageComponent` (through the component), CS Studio's media components, `config/initializers/public_site_version.rb`, `config/initializers/active_storage_access.rb`, `config/queue.yml`, `config/deploy.yml`, `config/environments/*` (Active Storage), `Settings::Save` and the Settings screen, `Setup::SystemCheck`, a site script, `db/schema.rb`, `docs/reference/media.md`, `hosting.md`, `theming.md`, `docs/roadmap.md`, `CLAUDE.md`.

| Finding | Here | What and why |
|---|---|---|
| Image delivery: stable cacheable URLs and a queue of their own for variants | **Closed** | Proxy mode with immutable headers (decision 2), a queue and worker of their own (5), the preview at upload instead of the original (1, 3), telemetry of latency and duration (5). |
| Every image change and publish empties every render cache on the site | **Part pulled in** | The asset's bump only when a live record uses it, and one bump per generation instead of one per variant (decision 4), both on this code path. Left: re-keying the rich-text render on what it reads and the publish's bump, which are the render cache's design and C1's, not images'. |
| No whole-page cache, and the content version costs four statements | **Not touched** | This work does not change `PublicSite.content_version` or the page's caching; fewer bumps make the existing caches warmer, nothing more. |
| The docs disagree on whether a CMS image is published | **Part pulled in** | This work edits `hosting.md`, `theming.md`, the roadmap and the install guide, so their wrong lines (`hosting.md:167`, `theming.md:770` and the item in `:800`, `roadmap.md:14` and `:176`, the guide's `install-and-first-start.md:48`) are corrected in it. Left: `Dockerfile:19` and `OUTLINE.md` in the docs repository, and the sweep rule the finding proposes. |
| Add a schema field type that refers to library images | **Seam kept, not built** | Decision 6: the bump rule reads `Media::UsageIndex`, so a `:media` field joins by feeding it. The type itself is its own work (gallery). |
| List every environment variable in one place | **Part pulled in** | `hosting.md` gains the job variables this work depends on (`SOLID_QUEUE_IN_PUMA`, `JOB_CONCURRENCY`, and any the builder adds for the images worker), with what they mean for images. Left: the full list and an `.env.example`. |
| Solid Cable polls ten times a second when nobody is signed in | **Part pulled in** | This work adds a worker to `config/queue.yml`, so it must not double the idle polls: the images worker polls at a longer interval (decision 5). Left: Solid Cable's 100 ms and the default worker's and dispatcher's interval. |
| Keep code comments about invariants, not plan steps and review rounds | **Part pulled in** | The comments of the files this work rewrites (`asset.rb`'s variant, `srcset`, bump and upload comments, `picture_component.rb`, `public_site_version.rb`) are written about the invariants they guard, without "fix round", "Task N" or "Review Focus" references. Other files are left. |
| Shrink CLAUDE.md to an index, the commands and the unguarded rules | **Part pulled in** | The rules this work adds go to CLAUDE.md as short rules naming their test file (no quoted test names), with the reasoning in `docs/reference/media.md`. Left: the rest of CLAUDE.md. |
| Split the reference docs and stop citing tests by their full name | **Part pulled in** | Same as above for `media.md`: the new section cites test files, not full test names. Left: the split. |
| Load admin scripts on demand, and give public pages their own import map | **Not touched, constrained** | The fade adds one top-level controller the public `site` entry point imports; it is small and has no pin of its own. The finding's lazy registration is not on this path and is left. |
| Make audit events a usable extension point | **Not touched** | The regenerate action is placed in `Editing::Signals::SILENT` as every action is; the finding's raise for unlisted actions does not apply to it. |
| A field type's behaviour is spread over seven core files | Not touched | Settings' fields are not schema field types. |
| Version the CMS: a version number, release tags and a changelog | Not touched | The `<img>` change needs a release note (constraints); where it is written follows whatever that work decides. |
| Remove compatibility code a pre-release CMS does not need | Not touched | `media:variants` stays as the console's regenerate. |
| Public read path: one path query per link, and lists that load every body | Not touched | The preview rides on the asset row already loaded; no new read per image. |
| Replace marker comments and exact-line allow-lists with structure | Not touched | This work adds `# version:` lines under the existing guard and changes no guard. |
| Registries other than block types are emptied before a gem can register | Not touched | |
| Content types are code-only, have no declarations, and ship the owner's site | Not touched | |
| Integrator kit: a site template, and theme work without a CMS checkout | Not touched | |
| Pages have no extensible fields | Not touched | |
| Slots fit one shape: no column, panel, sidebar entry or save answer | Not touched | |
| A routes hook must draw before the public catch-all and reserve its addresses | Not touched | Active Storage's routes are its own and unchanged. |
| A plugin's tables have no way into a site's database | Not touched | |
| Give gem authors the CMS's conformance checks | Not touched | |
| Split the largest scripts and controllers, and share one merge core | Not touched | |
| Lower the entry cost of writing a system test | Not touched | |
| Every browser test signs in through the form and lands on the dashboard | Not touched | |
| Local setup leaves first-day failures to every contributor | Not touched | |
| Client sites need editable appearance and site structure | Not touched | |
| The dev seed shows two of seven block types | Not touched | |
| One name for a person's short name | Not touched | |
| Plan the MCP page and block tools to serialise any block type from its schema | Not touched | The media tools' addresses are checked (left to the builder), not their shape. |
| Default a new site to one language | Not touched | |
| The page tree reads every page and is redrawn on every settings autosave | Not touched | |

## The owner's answers (2026-10-31)

1. The original is reachable by signed-in editors only; the public gets re-encoded widths with camera data dropped; the media panel offers "Download original"; the blob proxy refuses a library original to the public (decision 2).
2. Animated GIFs become animated WebP at each width; the original GIF is never served publicly (decision 1).
3. WebP is the default; AVIF is an opt-in with a line that older browsers then show nothing; one `<img>`, no `<picture>` (decision 7).
4. Saving settings changes nothing until "Regenerate images" is pressed; the card says how many images use old settings (decision 7).

No question is left for the owner.

## Questions for the Design System

Not decided here; the Design System's "Image loading" page, option C, is the starting point.

1. The preview-only state (no width yet): how blurred, and whether it is distinguishable from the loading state at all.
2. The fade's duration and easing, and whether the preview is blurred in the image or by CSS.
3. The `th-sunken` fallback box: plain, or with a mark?
4. CS Studio's tiles, panel and picker while an image's widths are being made: the same blur, or a quieter mark with "Being made" (and the wording)?
5. The Images card: its layout, how widths are entered and shown, how AVIF's slowness and an unavailable AVIF are said, how the card shows "N images made with other settings", the progress while regenerating, the confirmation dialog's words, and a failed count.
6. Whether a theme may restyle the loading state (which would make its attribute a contract name), or the look is the CMS's.
7. System status's Images row: its words in each state.
8. "Download original" in the media panel: where it sits and what it says.
