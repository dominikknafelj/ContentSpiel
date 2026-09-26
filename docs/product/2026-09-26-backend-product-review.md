# ContentSpiel admin: product review from a non-technical editor's point of view

Reviewed 2026-09-26 on the local dev instance (http://localhost:3000, Avo 4.2.4), signed in as the seed admin, acting as a marketing/comms editor. I did the jobs below in the browser and then checked each finding against `app/avo/**`, `app/models/**` and `app/views/**`.

Test data created (disposable dev DB): Post #8 "PM Review Spring Launch" (blog, tag `rails`, DE title, scheduled 2026-09-30 12:00), Page #8 "PM Review Campaign" (landing, draft, child of Home, 1 rich-text block and 1 post-list block), ApiToken #2 (created with "Regenerate my API token"; no token existed before; revoked afterwards because its raw value was lost with the toast). Nothing was deleted and the admin password was not changed.

---

## 1. Summary

ContentSpiel's backend works well for the developer who built it. A non-technical editor can't use it on their own yet. The data model is sound (page tree, blocks, per-field translations, scheduling via `published_at`), but the admin shows that model directly: raw enum values (`now_update`, `post_list`), numeric positions, hand-typed slugs, a JSON code editor for post metadata, and free-text `content_type` / `tag` / `limit` inputs for post lists. On the page form, rich text is a **raw HTML textarea**. There is no preview, no "View on site" link and no status column (draft / scheduled / live). An editor can't see a draft or scheduled item before it goes live: the public URL returns a bare "Not Found" even when signed in. Several inputs **silently do nothing**: the post-list *Tag* setting is never read, and on the create form the landing-page *Subtitle* and *Hero image* only appear after a first save, while a subtitle typed on the create form's re-render was dropped. The public site also ignores most of what editors set up: site title, tagline, logo, social links, post excerpts, dates, tags, related posts and resume metadata are never rendered. The home layout puts every block side by side in one row. Verdict: fine for a technical owner-operator. For the target persona it needs one focused round of editor-UX work (preview, status, typed block editors, hiding technical fields) before handover.

---

## 2. Friction log

| # | Area | What the editor tried | What happened | Why it hurts | Concrete fix idea | Severity | File:line |
|---|---|---|---|---|---|---|---|
| 1 | Landing | Opened `/avo` after sign-in | Avo's "Welcome to Avo" developer page (`bin/rails generate avo:resource …`, Pundit, add-on pricing) | First impression is developer docs. In production this page is hidden, so there is no real start page at all | Set `config.home_path` to a custom "Dashboard" tool: recent posts and pages, drafts, scheduled items, quick "New post / New page" buttons | major | `config/initializers/avo.rb` (no `home_path`) |
| 2 | Navigation | Looked for "Posts" in the sidebar | Alphabetical list: *Api tokens*, *Content blocks*, Pages, Posts, Site settings, Tags, Users, then Tools (Mind graph, Pages tree, System status, **Avo Status**) | The most-used items are buried and the technical ones come first. "Content blocks" as a top-level item invites editing blocks without their page | Custom `config.main_menu`: **Content** (Pages tree, Posts, Tags), **Site** (Settings, Users), **Advanced** (API tokens, System status). Hide Content blocks and Avo Status | major | `config/initializers/avo.rb`; `app/views/avo/sidebar/items/*` |
| 3 | Posts index | Scanned the list for drafts | Columns ID / `blog`/`resume_entry`/`now_update` / Title / Published at. A draft shows "—" and a scheduled post shows only a future date | Can't tell draft / scheduled / live at a glance. Raw enum strings. No search box | Computed `status` badge field (Draft / Scheduled / Live), humanized type labels, translation-coverage column (EN ✓ DE ✓ ES –), `self.search` on title | major | `app/avo/resources/post.rb:13-15,43` |
| 4 | Post: write | Created a blog post | Form has Content type, Title, **Slug**, Excerpt, Body, Published at, **Metadata `{}` code editor**. No tags field and no featured image | Slug and JSON are developer concepts. The editor has to save first, then use "Attach tag" on the Show page (3 clicks per tag, and only existing tags) | Tag multi-select with create-on-type on the form. Hide Metadata except for resume entries (see #10). Put Slug in a collapsed "URL & SEO" panel | major | `app/avo/resources/post.rb:36,44-45` |
| 5 | Post: image | Looked for "add an image" | Only way: paperclip button inside the Trix body (EN tab only). No cover or featured image | The listing and the social card can't show an image. Each locale needs its own upload | Add `has_one_attached :cover_image` with alt text to Post; render it in listings and `og:image` | major | `app/models/post.rb` (no attachment); `app/views/pages/_seo_meta.html.erb:13-25` |
| 6 | Post: schedule | Picked 30 Sep 12:00 in "Published at" | Worked, but nothing on the field says that empty = draft and a future date = scheduled. No timezone shown. Show page still says just "Published at 2026-09-30 12:00:00" | Scheduling is invisible, and it's easy to publish by accident (any past date) or leave something as a draft forever | Rename to "Publish date" with help text. Add actions "Publish now" / "Unpublish". Show a status badge and timezone | major | `app/avo/resources/post.rb:43`; `app/avo/resources/page.rb:91` |
| 7 | Preview | Opened `/blog/pm-review-spring-launch` while signed in | Bare "Not Found" page (unstyled, dark) | No way to proof a draft or scheduled post or page before it goes live | Signed-in preview (`?preview=1` honoured when `Current.user`, bypassing the `published` scope) plus a "Preview" / "View on site" button on Show/Edit | blocker | `app/controllers/pages_controller.rb` (published scope); `app/models/post.rb:32` |
| 8 | Translate post | Switched to the DE tab | Empty fields with no reference to the English text. **The DE Excerpt textarea rendered collapsed (0 px high)** until clicked. The DE slug was not generated (falls back to the English slug) | Translators work blind. The slug fallback isn't explained, so a German URL keeps the English slug | Show the EN source text as read-only hint text under each non-default field. Auto-fill the slug per locale from that locale's title. Add a "Copy from EN" action. Fix the textarea height in hidden tabs | major | `app/avo/resources/post.rb:29-40`; `app/models/post.rb:76-78` (slug only generated for the ambient locale, on create) |
| 9 | Tags | Attached tag `rails` | Worked via modal. Tag names are lowercase developer tags; nothing shows where tags appear on the site | Tags aren't rendered publicly and can't filter a post list (see #16), so tagging has no visible effect | Render tags on post detail and add tag archive pages, or de-emphasise tags until they do something | minor | `app/avo/resources/tag.rb`; `app/views/content_blocks/_post_list_detail.html.erb` |
| 10 | Resume entry | Tried to add a resume entry | Same form as a blog post. Company, role, dates live in **Metadata JSON** (`{"company":…,"role_type":"ic","start_date":…}`, see starter content). The public site never renders metadata | Editor has to type JSON with magic keys, and it has no visible effect anyway | Per-content-type fields: Company, Role, Start/End date pickers, "current role" checkbox, stored in `metadata` but shown as normal inputs (`visible:` by content_type). Render them in the resume listing | major | `app/avo/resources/post.rb:44`; `app/models/starter_content.rb:23`; no view reads `metadata` |
| 11 | "Now" update | Created mentally as a post with type `now_update` | Same full blog form (slug, excerpt, metadata) for what is a short status note | Too much ceremony for a one-paragraph update | Simplified form for `now_update`: body and date only; auto-slug from date | minor | `app/avo/resources/post.rb:15` |
| 12 | New page | Created "PM Review Campaign" (landing) | Save failed with toast "Slug can't be blank" (page slugs are not auto-generated, unlike posts). The error appeared only as a toast, not next to the field | The editor doesn't know what a slug is, and the error isn't next to the field | `before_validation` slug-from-title for Page, same as Post. Show the resulting URL preview ("/pm-review-campaign") under the title | major | `app/models/page.rb:66` (no generation); `app/avo/resources/page.rb:71` |
| 13 | New page: hero | Chose "landing" on the New form | Subtitle and Hero image fields only appear **after a save**. A subtitle typed into the re-rendered create form was **lost** (Show page: Subtitle "—"); the same value typed on Edit saved fine | Silent data loss. The hero is undiscoverable | Always show Subtitle and Hero on forms (help text "Landing pages only"), or two-step create. At minimum, don't drop submitted values (the `visible:` lambda evaluates against the unsaved record) | major | `app/avo/resources/page.rb:78-79,89` |
| 14 | New page: position | Saw "Position *" as the second field | Required-looking number box on create (ignored on create, required on update). Index shows 0-based positions | "What number do I type?" Positions are an implementation detail now that drag-and-drop exists | Remove Position from the page form entirely (Pages tree handles it) or show it as read-only "Order in menu" | major | `app/avo/resources/page.rb:53` |
| 15 | Page blocks | Added a rich-text block on the page form | Each block row shows **every** field for every type: Image, 3 post-list settings, 3 captions, 3 **"Body HTML (EN/DE/ES)" plain textareas**. Adding a block = pick type in the blank row, then Save. Removing = "Remove" checkbox, then Save | Editors can't write HTML. The form is very long (about 13 inputs per block). Type-specific fields aren't hidden. Nothing happens until you save | Per-type block editors: link each row to the block's own Trix form, or render only the fields for the chosen type (Stimulus toggle). Add "Add block ▾" buttons, up/down or drag, and a delete icon | blocker | `app/views/avo/partials/_content_block_row.html.erb:36-69`; `app/avo/resource_tools/nested_content_blocks.rb` |
| 16 | Post list block | Set Content type "Blog", Tag "Rails", Limit "3" | "Blog" rejected with toast "Content blocks settings content_type must be one of: blog, resume_entry, now_update". After fixing to `blog` it saved, but **the Tag setting is never read**, so the list isn't filtered | Free-text enum, error message in developer language, and one input silently does nothing | Content type dropdown (humanized), tag select from existing tags, number input for Limit. Implement the tag filter in `ContentBlock#listed_posts` (or remove the field) | blocker | `app/models/content_block.rb:62-67` (no tag filter); `_content_block_row.html.erb:41-49`; `app/avo/resources/content_block.rb:20-22` |
| 17 | Page blocks (accessibility) | Screen reader / label click on post-list inputs | The three settings inputs have `id: nil`, so their `<label>` isn't associated | Label click doesn't focus. Assistive tech reads unlabeled boxes | Give each input an id matching its label | minor | `_content_block_row.html.erb:44-46` |
| 18 | Page Show | Viewed the new page | "Content blocks" panel lists `ID / Position / Block type (rich_text) / Image` and offers **"Attach content block"** and **"Attach child"** | "Attach" re-parents an existing block or page from elsewhere. That's a footgun with jargon | Hide attach controls. Show a block preview (first line of text or a thumbnail) instead of ids | major | `app/avo/resources/page.rb:97-98` |
| 19 | Fix a typo | Tried to fix a typo on "About" | Path: Pages → About → Edit → find the block → edit raw `<div>…</div>` HTML. Or find the block id in "Content blocks" and use the Trix form there (block record title shown as `rich_text`/`post_list`) | 4-5 steps plus HTML literacy for a one-word fix | "Edit this page" link on the public site for signed-in users, and a WYSIWYG block editor (#15) | major | `app/avo/resources/content_block.rb:7`; `_content_block_row.html.erb:63-68` |
| 20 | Reorder pages | Dragged "PM Review Campaign" above "About" in Pages tree | Worked smoothly (drag handle), persisted | Good, but the tree can't create a child page, open the public page, or show scheduled pages as scheduled (the label only checks `published_at.present?`, so a future date shows "published") | Add "+ child", "View" and status badge (Draft / Scheduled / Live) per node. Make the tree the Pages landing view | minor | `app/views/avo/tools/_page_node.html.erb:21` |
| 21 | Navigation on the site | Expected the new page to appear in a menu | There is no header navigation, only a list of the current page's children under its content. Home is the only place top-level pages are listed | Editors can't control a menu ("show in navigation", menu label) | Header nav rendered from root's published children, plus per-page "Show in menu" and "Menu label" | major | `app/views/layouts/application.html.erb:27-31`; `app/views/pages/show.html.erb:33-41` |
| 22 | Public layout | Looked at the home page after editing | `<main class="… flex">` lays out title, rich text, post list and child nav **side by side in one row** | Whatever the editor builds looks broken, which undermines trust in the CMS | Stack blocks vertically (`flex-col` or no flex) with a content-width column | major | `app/views/layouts/application.html.erb:28` |
| 23 | Site settings | Changed site title / social links (form reviewed) | Form is fine (Title, Tagline, Social links key/value "Network / URL", Default locale, Logo). **None of title, tagline, logo or social links is rendered publicly**: `<title>` falls back to "ContentSpiel", no header or footer | Editor changes settings and sees no effect anywhere | Render site title and logo in the header, social links in the footer, `"Page – Site title"` in `<title>`. Translate the tagline. Network as a dropdown with icons | major | `app/views/layouts/application.html.erb:4,27-31`; `app/avo/resources/site_setting.rb:15-27` |
| 24 | Site settings: locale | Looked at "Default locale" | Options EN/DE/ES; changing it re-routes every URL immediately (per the code comment) with no warning | One click changes every public URL (SEO and bookmarks) | Help text explaining the effect, plus a confirmation step | minor | `app/avo/resources/site_setting.rb:25-26` |
| 25 | SEO | Looked for SEO on a page | Page has Meta title / Meta description per locale with no help, character counter or snippet preview. **Posts have no SEO fields** (title and excerpt reused). No OG image. No canonical, hreflang or noindex | Editors don't know what the fields do or how they look in Google | "Search & social" panel: counters (60/155), Google-snippet preview, OG image, noindex toggle. Add hreflang alternates for translations | minor | `app/avo/resources/page.rb:81-82`; `app/helpers/pages_helper.rb:14-22`; `app/views/pages/_seo_meta.html.erb` |
| 26 | Media | Looked for "where do I upload images" | No media section. Images are uploaded per field (hero, image block, logo, inline Trix). No alt text anywhere. Block and hero images are served at original size | Can't reuse an image, can't find past uploads, accessibility gap (no alt), slow pages | Known deferred (spec §7). Short term: add an alt-text field to image blocks and hero | major | `app/views/content_blocks/_image.html.erb:3`; `app/views/pages/show.html.erb:11` |
| 27 | MCP token | Ran Actions → "Regenerate my API token" | The raw token is shown **only in an auto-dismissing success toast**. It was gone within seconds (by my next screenshot). The index then shows a bcrypt `token_digest`, "User" as the number `1`, and `Revoked at` as an editable date-time | An editor who blinks loses the token and has to regenerate. The digest is noise. Revoking means typing a date. No instructions on how to connect an AI client | Show the token in a persistent modal/page with a Copy button and the MCP endpoint URL plus a config snippet. Hide the digest. Label tokens (name, created at). Add a "Revoke" action. Make User show the email (`self.title = :email_address`) | major | `app/avo/actions/regenerate_api_token.rb:18`; `app/avo/resources/api_token.rb:13-21`; `app/avo/resources/user.rb` (no title) |
| 28 | MCP token (empty state) | Opened Api tokens with no tokens | "No record found" and no Create button. Creation is hidden in the "Actions" menu | Dead end for first-time users | Empty-state text and button "Create a token for your AI assistant" | minor | `app/avo/resources/api_token.rb:36-38` |
| 29 | Users | Tried inviting a colleague | New user form: Email, Password, Password confirmation. No name, role or invite email (mail not configured, see System status) | Admin has to invent and share a password. Everyone is a full admin (can see tokens, change settings) | Invite link flow (show a one-time set-password URL if mail is off). Roles are deferred (spec §7) | major | `app/avo/resources/user.rb:12-20` |
| 30 | Mind graph | Opened it | Read-only force graph of posts. Relations are created from the post Show page ("Attach related post") | Nice to have, but "Mind graph" isn't an editor term and you can't link posts from it. Related posts are never shown on the public site | Rename to "Related posts map", allow creating a link by dragging node to node, render "Related posts" on post detail | minor | `app/controllers/avo/tools_controller.rb:42-62`; `app/views/avo/tools/mind_graph.html.erb` |
| 31 | Post detail on site | Opened `/blog/building-contentspiel` | Title and body only: no date, author, excerpt, tags, related posts, cover image, or "back to blog" link | Editors expect what they entered to show up | Post detail template with date, tags, related posts, cover image | major | `app/views/content_blocks/_post_list_detail.html.erb:4-7` |
| 32 | Post list on site | Viewed the Home post list | Titles only (no date, excerpt or image). Drafts correctly hidden | Excerpt is filled in the admin but used only as the meta description | Card layout with date, excerpt and cover image | minor | `app/views/content_blocks/_post_list.html.erb:11-15` |
| 33 | Feedback | Saved forms repeatedly | Success and validation messages appear only as bottom-right toasts. Validation errors are not shown inline on the fields (e.g. slug, settings) | On a 13-inputs-per-block form, the editor can't find what to fix | Inline field errors (Avo supports them for declared fields; the resource-tool rows need their own error rendering) | minor | `_content_block_row.html.erb` (no error output) |
| 34 | Chrome / labels | General | Admin title is "Content spiel" (humanized app name, not the site's title). Record titles for blocks are `post_list` / `rich_text`. Content types show as `now_update` | Feels unfinished and technical | `config.app_name = -> { SiteSetting.instance.title }`; humanize every enum via `options:` labels | minor | `config/initializers/avo.rb`; `app/avo/resources/content_block.rb:7,13`; `post.rb:15`; `page.rb:55` |
| 35 | Dev-only link | Page header | Resource headers include a `cursor://file//Users/.../post.rb` link (Avo dev feature) | Dev only, so harmless in prod, but confusing during demos or handover on a dev box | Leave as is. Just note it when demoing to non-developers | minor | Avo dev mode |

---

## 3. Technical fields audit

| Resource / place | Field as the editor sees it | What it exposes | Editor-friendly replacement |
|---|---|---|---|
| Post (`post.rb:13`), Page (`page.rb:33`), Tag, ContentBlock, ApiToken, SiteSetting | `ID` column / field | DB primary key | Hide on forms and Show; keep off index |
| Post (`post.rb:15`) | Content type select `blog` / `resume_entry` / `now_update` | Raw enum keys | Labels "Blog post / Resume entry / Now update", ideally chosen *before* the form (three "New …" buttons) so the form adapts |
| Post (`post.rb:36`), Page (`page.rb:71`) | `Slug` (per locale) | URL segment; required on pages; uniqueness rules | Auto-generated from title per locale; shown as an editable "URL: /blog/**my-post**" preview in an "URL & SEO" section; warn when changing a published slug |
| Post (`post.rb:44`) | `Metadata` code editor showing `{}` | jsonb column | Typed fields by content type (resume: Company, Role, Start/End date, Current). Hide for blog/now |
| Post (`post.rb:43`), Page (`page.rb:91`) | `Published at` date-time | Nullable timestamp doubling as draft/schedule flag | "Status: Draft / Publish now / Schedule for…" radio with date picker; status badge |
| Page (`page.rb:53`), page block rows (`_content_block_row.html.erb:24-25`), ContentBlock (`content_block.rb:12`) | `Position` number | closure_tree / list order, 0-based | Drag handle (tree already exists) or ↑/↓ buttons; never a number |
| Page (`page.rb:44`) | `Parent` dropdown + "Create new parent" link | closure_tree parent_id; nested modal create | "Place under" picker showing indented tree; drop "Create new parent" |
| Page (`page.rb:55`) | `Page type` `standard` / `landing` with fields that appear only after save | enum + server-side `visible:` | "Layout: Standard / Landing (with hero)" with the hero fields always visible and labelled |
| Page form blocks (`_content_block_row.html.erb:63-68`) | `Body HTML (EN/DE/ES) (rich text blocks)` textareas | Raw ActionText/Trix HTML | Trix (or similar WYSIWYG) editor for the chosen locale only |
| Page form blocks (`_content_block_row.html.erb:41-49`) and ContentBlock (`content_block.rb:20-22`) | `Content type / Tag / Limit (post list blocks)` free text; ContentBlock form: `settings` key/value editor with "Setting / Value" | jsonb `settings` keys | Content-type dropdown (incl. "All"), tag picker (working!), number stepper "Show up to N posts" |
| Page form blocks | `Type —` blank row + `Remove` checkbox | `accepts_nested_attributes_for` mechanics (`_destroy`, reject_if) | "Add block ▾ (Text / Image / Post list)" buttons; trash icon with undo |
| Page form blocks | `Caption (EN)/(DE)/(ES) (image blocks)` all at once | per-locale Mobility accessors | Caption for the current locale tab only, plus an "Alt text" field |
| Page Show (`page.rb:97-98`) | "Attach content block", "Attach child" | Re-parenting belongs_to records | Remove; use "Add block" / "Add child page" |
| ContentBlock resource (`content_block.rb:1-39`) | Whole top-level resource, title `rich_text`/`post_list`, `Page` belongs_to select | Implementation table | Hide from sidebar; blocks are only edited inside their page |
| Page (`page.rb:81-82`) | `Meta title`, `Meta description` | SEO meta tags | "Search engine title/description" with counters and snippet preview |
| SiteSetting (`site_setting.rb:17`) | Social links key/value "Network / URL" | jsonb hash | Rows with Network dropdown (GitHub, LinkedIn, Mastodon, …) + URL validation |
| SiteSetting (`site_setting.rb:25`) | `Default locale` EN/DE/ES | Routing default, URL prefixing | "Main language of your site" with an explanation of URL effects + confirm |
| ApiToken (`api_token.rb:13-21`) | `Token digest` (bcrypt hash), `User` shown as `1`, editable `Revoked at`, `Last used ip` | Security internals | Name/label, created, last used ("2 days ago"), status (Active/Revoked), "Revoke" button; hide digest; user by email |
| Actions menu (`regenerate_api_token.rb`) | Token delivered in a transient toast | Flash message | Persistent reveal screen with Copy button + MCP URL + client config snippet |
| Sidebar | "Avo Status", "System status", "Api tokens", "Content blocks" | Framework/ops internals | Group under "Advanced" or hide for editors |
| Users (`user.rb:15-19`) | Password + confirmation set by admin | has_secure_password | Invite by email / one-time set-password link |

---

## 4. Missing user stories

Legend: **Deferred** = listed in setup-wizard spec §7 (runtime languages, roles/permissions, media library/image processing, production mail, theming). **New** = not in that list.

### Authoring & editing
- As an editor, I want a WYSIWYG editor for every text block on a page, so that I never have to write HTML. **Must**. New.
- As an editor, I want block forms that only show the fields for the block type I picked, so that the page form stays short and understandable. **Must**. New.
- As an editor, I want to add, reorder (drag or ↑/↓) and remove blocks with immediate visual feedback, so that composing a page feels direct. **Should**. New.
- As an editor, I want typed fields for resume entries (company, role, dates), so that I don't have to write JSON. **Must**. New.
- As an editor, I want a revision history with "restore previous version", so that I can undo a mistake after saving. **Should**. New (WordPress/Craft/Kirby all have this).
- As an editor, I want autosave or an "unsaved changes" warning, so that I don't lose a long post. **Could**. New.
- As an editor, I want to duplicate a page or post, so that I can start from an existing layout. **Could**. New.
- As an editor, I want search across posts and pages in the admin, so that I can find the item with the typo quickly. **Should**. New.

### Media
- As an editor, I want a media library to browse, reuse and replace uploaded images, so that I don't upload the same file repeatedly. **Should**. Deferred.
- As an editor, I want to enter alt text for every image, so that the site is accessible and SEO-friendly. **Must**. Deferred (metadata mentioned in §7), but alt on existing fields can ship now.
- As an editor, I want images automatically resized to web sizes, so that pages stay fast even when I upload phone photos. **Should**. Deferred.
- As an editor, I want a cover image per post, so that listings and social shares look good. **Should**. New.

### Pages & navigation
- As an editor, I want page slugs generated from the title, so that creating a page never fails on a field I don't understand. **Must**. New.
- As an editor, I want to control which pages appear in the main menu and with what label, so that I can shape the site navigation. **Must**. New.
- As an editor, I want to add a child page and open the live page directly from the Pages tree, so that the tree is my home base for site structure. **Should**. New.
- As an editor, I want a warning (and ideally an automatic redirect) when I change the slug of a published page, so that old links don't break. **Should**. New.
- As a site owner, I want a footer with social links and legal pages (Imprint/Privacy), so that the site meets basic legal expectations (DE market). **Should**. New.

### Publishing workflow & preview
- As an editor, I want to preview a draft or scheduled page/post exactly as it will look, so that I can proof it before it goes live. **Must**. New.
- As an editor, I want a clear status (Draft / Scheduled / Live) on lists, forms and in the tree, so that I know what visitors can see. **Must**. New.
- As an editor, I want "Publish now" / "Unpublish" / "Schedule…" buttons, so that publishing isn't done by editing a timestamp. **Must**. New.
- As an editor, I want a "View on site" link from every page and post, and an "Edit" link on the public site when I'm signed in, so that I can jump between the two. **Should**. New.
- As an editor, I want a dashboard showing recent edits, drafts and upcoming scheduled items, so that I know what needs attention. **Should**. New.
- As a reviewer, I want to share a private preview link with a colleague who has no account, so that I can get sign-off. **Could**. New.

### Translations
- As a translator, I want to see the source-language text next to each field I'm translating, so that I don't have to switch tabs constantly. **Must**. New.
- As a translator, I want per-item translation status (which locales are complete), so that I know what's missing. **Should**. New.
- As a translator, I want slugs generated per language from the translated title, so that German URLs are German. **Should**. New.
- As a visitor, I want a language switcher on the public site, so that I can read the content in my language (otherwise the translations aren't reachable). **Must**. New.
- As a site owner, I want to add or remove languages without a developer, so that the site can grow into new markets. **Could**. Deferred.
- As a site owner, I want site title and tagline translatable, so that the German site doesn't show an English tagline. **Could**. New.

### SEO
- As an editor, I want character counters and a search-snippet preview for meta title and description, so that I write good snippets. **Should**. New.
- As an editor, I want SEO fields and an OG image on posts too, so that shared blog posts look right on social media. **Should**. New.
- As a site owner, I want hreflang alternates and a canonical URL generated automatically, so that search engines understand my translations. **Should**. New.
- As an editor, I want a "hide from search engines" toggle per page, so that thank-you or campaign pages aren't indexed. **Could**. New.
- As an editor, I want a redirect manager (old URL → new URL), so that I can keep traffic after restructuring. **Could**. New.

### Users & roles
- As an admin, I want to invite a colleague by email (or one-time link) instead of setting their password, so that credentials aren't shared. **Must**. New (flow) plus Deferred (mail).
- As an admin, I want Editor vs Admin roles, so that editors can't change site settings, users or API tokens. **Should**. Deferred.
- As an editor, I want to see who last changed a page and when, so that I know whom to ask. **Could**. New.
- As a user, I want to reset my own password via email, so that I don't need a developer console. **Should**. Deferred (production mail).

### Site settings & theming
- As a site owner, I want the site title, logo, tagline and social links I configure to appear on the public site, so that my settings have a visible effect. **Must**. New (it's a rendering gap, not theming).
- As a site owner, I want to choose colours/fonts or a theme, so that the site matches my brand. **Could**. Deferred.
- As a site owner, I want to upload a favicon, so that browser tabs show my brand instead of the default icon. **Could**. New.

### AI / MCP
- As an editor, I want a guided "Connect an AI assistant" screen that shows my token once in a copyable box plus the MCP URL and config snippet, so that I can set it up without developer help. **Must**. New.
- As an editor, I want named tokens that I can revoke with one click and see "last used", so that I can manage several assistants safely. **Should**. New.
- As an editor, I want posts created by the AI to land as drafts marked "created by AI", so that nothing goes live without my review. **Should**. New.
- As an editor, I want the AI to also manage pages or blocks (not just posts), so that it can help with the whole site. **Could**. New.

### Ops
- As a site owner, I want the System status page to explain warnings in plain language with a "who to contact" note, so that I'm not asked to run `bin/rails console`. **Could**. New.
- As a site owner, I want a one-click content export (JSON/Markdown + images), so that my content isn't locked in. **Could**. New.
- As a site owner, I want the sitemap regenerated automatically on publish, so that search engines see new content without a rake task. **Should**. New.

**Counts:** Must 14 · Should 21 · Could 13 (48 total). Deferred (fully or partly): 8. New: 40.

---

## 5. Top 10 recommendations (editor impact vs effort)

| # | Recommendation | Impact | Effort | Touches |
|---|---|---|---|---|
| 1 | **Fix the public layout and render what editors configure**: vertical block stack; header with site title, logo and menu; footer with social links; `<title>` with site name; post date, excerpt and tags in listings and detail. Otherwise nothing an editor does looks right | Very high | S | `layouts/application.html.erb:4,28`, `content_blocks/_post_list*.erb`, `pages/show.html.erb` |
| 2 | **Replace raw post-list settings with real inputs and make Tag work** (content-type dropdown, tag select, number field; implement the tag filter in `listed_posts`) | High (silent no-op today) | S | `_content_block_row.html.erb:41-49`, `content_block.rb:62-67`, `content_block.rb (Avo):20-22` |
| 3 | **Auto-slugs for pages and every locale; move Slug and Position out of the way** (URL preview line; drop Position from the page form now that the Pages tree exists) | High | S | `models/page.rb:66`, `models/post.rb:76-78`, `avo/resources/page.rb:53,71` |
| 4 | **Status and publish controls**: Draft/Scheduled/Live badge on indexes, Show and tree; "Publish now / Unpublish" actions; help text on the date field; fix the tree's "published" label for future dates | High | S–M | `post.rb`, `page.rb`, new `app/avo/actions/*`, `_page_node.html.erb:21` |
| 5 | **Signed-in preview + "View on site" / "Edit this page" links** | High | M | `pages_controller.rb`, `post.rb:32`/`page.rb:46` scopes, Avo resource controls |
| 6 | **WYSIWYG, type-specific block editing on the page form** (show only fields for the chosen type, Trix instead of "Body HTML", per-locale tab instead of all three at once, add/remove buttons) | Very high | M–L | `_content_block_row.html.erb`, `nested_content_blocks.rb`, a Stimulus controller |
| 7 | **Typed resume fields instead of Metadata JSON; slim "Now" form; tags and cover image on the post form** | Medium-high | M | `avo/resources/post.rb:44-45`, `models/post.rb`, resume listing view |
| 8 | **Editor-first admin shell**: custom home dashboard, grouped sidebar (hide Content blocks, Avo Status; move API tokens/System status to Advanced), humanized enum labels, `app_name` = site title, User title = email | Medium-high | S | `config/initializers/avo.rb`, all resources' `enum:` → `options:` |
| 9 | **Safe token onboarding**: persistent one-time reveal with Copy, MCP URL and config snippet; hide digest; Revoke action; empty-state CTA | Medium (blocks the AI story) | S | `regenerate_api_token.rb`, `api_token.rb` |
| 10 | **Translation ergonomics + public language switcher**: source text under each translated field, completeness indicator per item, fix collapsed textarea in hidden tabs, switcher in header | Medium-high (translations are invisible to visitors today) | M | `post.rb`/`page.rb` tabs, layout, `pages_helper.rb` |

Also fix now, because they lose data or do nothing: landing Subtitle/Hero dropped on create (`page.rb:78-79,89`), unlabeled settings inputs (`_content_block_row.html.erb:44-46`), and the "Attach content block / Attach child" controls on Page Show (`page.rb:97-98`).
