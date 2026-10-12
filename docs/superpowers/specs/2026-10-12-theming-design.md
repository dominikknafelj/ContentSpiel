# Theming as a real mechanism

Date: 2026-10-12. Status: design, with the owner's answers of 2026-10-12 recorded under "Decisions"; the plan is `docs/superpowers/plans/2026-10-12-theming.md`. Roadmap "Next", item 2 (decisions D7 to D12 of the brainstorm of 2026-10-11). Evidence: the spike (`docs-theme-spike`, never to be merged) and the one real theme it drew, `contentspiel-docs/theme`, with its findings in that repository's `SPIKE.md` (numbers below as "finding 3").

## Why

A site that is not the demo has no way to look like itself. The public templates, the stylesheet's build paths and the token values all live inside the CMS; `Theme.current` is one object with one method and nothing names a folder. The documentation site, the first real integration, could be drawn only by a branch that is not to be merged. And nothing says which names a theme may rely on, so every change to a public template could break a site without anyone knowing.

## What a person gets

- An integrator keeps a **theme folder** in the site's own repository (templates, a stylesheet, images, fonts, small scripts), sets one variable, `THEME_PATH`, and the site is drawn by it. Whatever the folder does not hold comes from the default theme.
- A written **contract**: the token names, the templates a theme may replace, what each receives, the helpers it may call. The CMS says in its release notes when one of them changes; everything else may change freely.
- `bin/rails 'theme:new[PATH]'` writes a copy of the default theme in the folder's shape, and `bin/rails theme:check` says what is wrong with a folder before a visitor finds out.
- An administrator reads in the boot log and under System status which theme draws the site.
- An editor gets nothing new: no block, no field, no setting.

## Decisions

Decisions 1 to 6 are the owner's (D7 to D12, and the environment variable, 2026-10-12). Decisions 7 to 18 were made in this design and put to the owner on 2026-10-12; each says how it was answered. "Confirmed" is the owner's yes. "Accepted" is a decision that was explained and met no objection. One limit, in decision 12, is neither yet and says so.

1. **Three layers inside the CMS, no design-system repository** (D7): tokens and base styles, which know nothing of blocks; block styles and templates on those tokens; a site's own values. Each knows only the one before it.
2. **The token set is a contract** (D8): named, documented, stable; every default block is styled only through it.
3. **The CMS always renders the site and ships a default theme** (D9). Appearance settings in CS Studio and a content API are not this work.
4. **A theme is a folder in the site's repository, layered onto the CMS by deployment** (D10). The theme first, the default theme behind it. Not a gem, an engine, a fork or templates in the database.
5. **A theme may replace tokens, styles and any template of the contract, and brings no block types or settings** (D12).
6. **One environment variable, `THEME_PATH`**, validated when the application starts, announced in the boot log and shown in System status, as `PUBLIC_HOST` is.
7. **The read-only data the documentation theme needs is part of this work** (§7; confirmed 2026-10-12): one section's page tree at any depth with the shown page marked, previous and next, a page's ancestors, an article's headings with an id on each. Not part of it: search, a summary field, a group heading that is not a page, the frame option on images, the product's version, a header link that leaves the site, and the Code, Note and Table blocks.
8. **A theme holds no Ruby** (confirmed 2026-10-12: "maybe later, but not for now"). It cannot bring a helper, a component class or an initializer; what a template needs to compute is a CMS helper. Rejected: autoloading a `lib/` of the theme, which would make every internal class of the CMS something a theme can depend on.
9. **A block's template is replaced through `Theme#component_for`, not through the view path** (§3; accepted 2026-10-12: a technical decision, put to the owner, no objection). Rejected: the spike's override of `ApplicationComponent.sidecar_files`, which works but compiles the theme into the CMS's own classes, so a process can hold one theme and no test can draw two.
10. **The CMS writes the plumbing of `<head>`; everything in it that is look or voice is the theme's** (§2; agreed with the owner 2026-10-12, who asked: "if it's the frontend it should be part of it"). The CMS keeps the doctype, `<html>`, the `<head>` element and the tags a site breaks without (the list is in §2 and a theme cannot remove one of them). The theme has the pattern of the page title, the favicon and touch icons, its fonts, the theme-colour meta and any other tag of its own, and the whole frame inside `<body>`. Rejected: replacing `layouts/application.html.erb` whole, as the spike had to, which made the theme copy the CSP tag, the light/dark script, hreflang and the import map, and lose every tag the CMS adds later.
11. **One public stylesheet, built once when the image is built, from the default theme's styles and then the theme's** (§4; confirmed 2026-10-12). Rejected: a theme's stylesheet served alone (the spike), which made the theme copy every token and left every template it did not replace unstyled.
12. **How rich text looks is entirely the theme's** (§5; the owner, 2026-10-12: "Rich text output is subject to the theme"). Every element of a text (headings, paragraphs, lists, quotes, links, images, inline code, code blocks, rules, an embedded video) is styled by the theme, through the tokens and its own CSS, by the element selectors and class names the contract lists. **One limit, raised with the owner and not yet objected to (not confirmed):** a theme does not replace the HTML structure a text is rendered to (§5 says why).
13. **A theme's fingerprint is part of the public ETag** (§6; accepted 2026-10-12: a technical decision, put to the owner, no objection), so a changed theme is never answered 304 whatever the deploy revision says.
14. **The folder is checked strictly when the application starts, and a template that raises is an error, not a fallback** (§8; confirmed 2026-10-12). A file the contract does not name stops the boot. Rejected: ignoring unknown files (a misspelt `pages/shwo.html.erb` would silently never be used) and rescuing a failing template with the default one (a page half of one theme and half of another, and a bug nobody sees).
15. **The default theme's templates stay where Rails and ViewComponent put them** (`app/views`, beside each component); `bin/rails theme:new` is how it is "the example to copy" (confirmed 2026-10-12). Rejected: moving them into a theme-shaped folder loaded through the same mechanism, which moves every public template away from its convention for the sake of one copy command.
16. **The theme reaches the container as an image layer on the CMS image, never as a mounted volume** (§9; explained to the owner 2026-10-12, no objection: accepted). A volume could change without a build, and the stylesheet, the digested assets and the import map are all made at build time. For a person this means: changing the theme of a running site is a build and a deploy, and in development you edit a file and reload the page.
17. **A heading's id is made from the heading's text** (§7; explained to the owner 2026-10-12, no objection: accepted). The consequence: rewording a heading changes its id, so a link to that heading from elsewhere stops landing on it (the page still opens, at its top). The later alternative is an anchor stored on the heading, which the editor shows and a rewording keeps; it is rich-text work and is on the roadmap entry, not here.
18. **No block is added here, and the contract is written so that a block added later joins it by one entry** (decided 2026-10-12). A "Code" block (source, language, an optional file name, a copy button, coloured on the server, its syntax colours as theme tokens) is being designed in parallel as its own pull request, built right after this one. A block type joins the contract by its component's line in `Theme::Contract::COMPONENTS` (which makes its template replaceable and `theme:new` copy it) and its tokens' lines in `Theme::Contract::TOKENS`; nothing else in the mechanism names a block.

## 1. The folder and its variable

```
<theme>/
  views/layouts/public/   _frame, _head, _title, _icons, _header, _footer, _language_switcher, _theme_toggle
  views/pages/            show, not_found
  views/theme/            the theme's own partials, any names
  components/             a contract component's template, by the component's path:
                          components/blocks/image_component.html.erb
  assets/stylesheets/theme.css
  assets/images/  assets/fonts/
  javascript/controllers/ *_controller.js
```

`lib/theme_folder.rb`, beside `lib/site_address.rb` and required by `config/application.rb` the same way: plain Ruby that reads `THEME_PATH`, answers `ThemeFolder.current` (`configured?`, `path`, `fingerprint`, its files) and raises `ThemeFolder::Invalid` with a message that names the variable and the file. Unset means the default theme. The test environment ignores the variable (and `test/test_helper.rb` removes it before the application loads, as it removes `PUBLIC_HOST`), so a developer's shell never changes a test run; tests hand a folder in.

`Theme` (`app/values/theme.rb`) is the runtime side: `Theme.current` is built from `ThemeFolder.current` inside `to_prepare`, as every registry is, and a test swaps it for the length of a block (`Theme.with(theme) { … }`). It answers `views_path`, `component_for(definition, role)`, `fingerprint` and `name` (the folder's base name, for the log).

The boot log says one line: `Theme: /rails/site-theme (14 templates, fingerprint 3fa9c1d2)` or `Theme: the default theme (THEME_PATH is not set)`. `Setup::SystemCheck` gains a "Theme" row with the same fact, and a warning when a theme is set in production and the built stylesheet is not that theme's (§4).

## 2. Page templates and the frame

`PublicPageRendering`, the concern `PagesController` and `PreviewController` both include, prepends `Theme.current.views_path` in a `before_action`, per request. CS Studio's controllers do not include it, so a theme can never reach an admin view.

`layouts/application.html.erb` stays the CMS's and is not in the contract: the doctype, `<html>`, `<head>` and `<body>` with the preview bar. Inside the body it renders `layouts/public/_frame`, which is the theme's: the default one holds today's column, header, `<main>` and footer. The classes on `<body>` are the default theme's and read tokens only, so a theme changes the page's ground and type by its tokens or by a `body` rule of its own. The preview bar is product UI on a public page and no theme replaces it.

**The head is split by who answers for a tag** (decision 10).

The CMS writes these, in this order, and a theme cannot remove or replace one of them:

- the `<title>` element (its text is the theme's, below);
- `<meta name="viewport">`;
- the content security policy's tag (`csp_meta_tag`);
- the script that picks light or dark before the first paint (`shared/_theme_head`);
- the description and the Open Graph tags, with the address of what is shown (`pages/_seo_meta`);
- the canonical link and the language links (`hreflang`, `x-default`);
- the stylesheet link and the import map with its scripts;
- and, as a decision and not a tag: no CSRF token on a public page, which is the same cookie-less answer for every visitor.

The theme has, each as a partial under `views/layouts/public/` with the default theme's as the fallback:

- **`_title`: the pattern of the page title.** It receives `page_title` (the page's or the post's own title; nil on the homepage and on a 404) and `site_title`, and its output, with the white space around it removed, is the text of `<title>`. The default writes "Page – Site" and the site's title alone when there is no page title; a theme that wants "Site | Page" writes that one line. A template, not Ruby (decision 8). Two things stay the CMS's: a meta title an editor typed for a page is taken as written and the pattern is not asked, and the Open Graph title is the page's own without the site's name. One visible change follows: a 404's title is now the site's title through the pattern, where the layout printed the literal "ContentSpiel".
- **`_icons`: the favicon and the touch icons.** The default links `/icon.png` and `/icon.svg` as today; a theme links its own files from `assets/images` with `image_path`.
- **`_head`: every other tag of the theme's own**, rendered last before the stylesheet: fonts to preload (`preload_link_tag` on a file in `assets/fonts`; the `@font-face` rules are in the theme's stylesheet), `<meta name="theme-color">` (two tags with `media` for light and dark, if the theme wants both), a verification tag. The default holds the three "installable app" metas the layout had (`application-name` among them), so a site that is not the demo no longer announces itself as "ContentSpiel" once its theme brings its own `_head`.

Fonts and scripts from another host are not a theme's to add: the content security policy is the CMS's. A theme ships its font files.

`pages/show` and `pages/not_found` hold what goes inside the frame's `<main>` and nothing else: the two lines `pages/show` carried for the CMS (the head tags of `pages/_seo_meta` and the preview bar) move into the layout, so a theme that replaces the page template cannot lose them.

Replaceable through the view path: the frame, the three head partials, the header, footer, language switcher and theme toggle, `pages/show`, `pages/not_found`. Not replaceable: the layout, `pages/_seo_meta`, `shared/_theme_head`, `layouts/public/_preview_banner`.

## 3. Block and post templates (obstacle 1)

ViewComponent finds a template beside its class and never asks the view path. `Theme#component_for` is already the one place the public site gets a block's, a post list's or a post's component from (`ThemeHelper#render_block`, `Blocks::PostListComponent`). For a component whose template the folder holds, it answers a subclass that the theme generates once (`Class.new(component)`, with `sidecar_files` answering the theme's file) and that is otherwise the CMS's class. The template is therefore compiled into a class of the theme's own, calls everything the default template calls, and the CMS's class keeps its own template. The subclasses are rebuilt in `to_prepare`, and `config.watchable_dirs` gains the folder so a changed template reloads in development.

So the replaceable components are exactly those the type registries hand out, each one line of `Theme::Contract::COMPONENTS` (decision 18: a block type added later adds its line, and a test fails for a component a registry hands out that the list does not hold): `Blocks::RichTextComponent`, `ImageComponent`, `PostListComponent`, `SectionComponent`, the three post list components and `Posts::DetailComponent` (which is "a post's layout"). `Media::PictureComponent` is called by templates, not replaced; `RichText::ImageComponent` and `YoutubeComponent` are rich text (§5).

**What a template receives** is written per component in the contract: Rich text `block`, `page`; Image `block`, `asset`, `alt`, `caption`, `sizes`; Section `columns`, `layout`, `background`, `width`; Post list `list_component`; a list component `posts`, `page`; the detail `post`. Each listed method is made safe for an empty block (`caption` raises today without an image, finding 3). A method not on the list is the CMS's to change.

The plan's first task proves the generated subclass against ViewComponent 4.15 with a failing test first. If the gem refuses it, the fallback is the spike's override, at the price named in decision 9.

## 4. The stylesheet (obstacle 2)

`theme_css:build` no longer has fixed paths. It writes an entry file to `tmp/theme/entry.css` and builds `app/assets/builds/theme.css` from it (the stylesheet is renamed from `theme-default`; the layout links the one name):

```
@import "<default theme>/theme.css";        tokens, base, prose, sections, the default templates' utilities
@source "<theme>/views"; @source "<theme>/components";
@import "<theme>/assets/stylesheets/theme.css";
```

with paths written relative to the entry file. Without a theme only the first line is there, which is today's build. What follows from the order:

- A theme changes a token by declaring it again (`:root { --th-accent: … }`, and under `[data-theme=dark]`). It copies nothing.
- A template the theme does not replace is still styled, because the default theme's styles are always in the build. That is what makes the fallback real, and it is why the preview bar keeps its look under any theme.
- A theme may write plain CSS (the documentation theme does) or Tailwind utilities in its templates: both go through the same executable, and the theme's templates are scanned.
- The cost is the default templates' utilities in every site's stylesheet, a few kilobytes a site does not use.

**When.** At image build, never at boot: the site's image runs `assets:precompile` again with `THEME_PATH` set, which builds the stylesheet and digests the theme's assets. The build writes the folder's fingerprint to `app/assets/builds/theme.stamp`; in production a theme whose fingerprint is not the stamp's stops the boot with "the stylesheet was built for another theme: run assets:precompile with THEME_PATH set". The one boot that is let through is the build's own: `assets:precompile` starts production before the stylesheet exists, and it runs with `SECRET_KEY_BASE_DUMMY`, which is what the check asks, as the secret's check does. In development `theme_css:watch` (already in `Procfile.dev`) watches the same entry.

**Layers.** `tokens.css` imports nothing and names no block; `prose.css` and `sections.css` and the default templates use tokens and no colour literal. `--th-*` is the CMS's namespace; a theme's own custom properties take another prefix. `--th-preview-*` and `--th-ph-*` are the CMS's own and not in the contract.

**Images and fonts.** `assets/images` and `assets/fonts` go on Propshaft's load path and are named in the stylesheet by file name; Propshaft writes the digested address. A file named like one the CMS ships stops the boot (a theme adds assets, it does not shadow them). The CMS's two font families reach a theme through `--th-font` and `--th-mono`, not through their file names.

**Scripts.** A theme's Stimulus controllers are pinned from `javascript/controllers` under `controllers/theme/`, so `copy_controller.js` is the identifier `theme--copy` and cannot collide with one of the CMS's (the folder `javascript` goes on the asset path, so the file is served as `controllers/copy_controller.js`, and one named like a controller of the CMS's own is a shadowing asset and stops the boot); They are registered by a third entry point, `site` (`app/javascript/site.js`: `application` plus `controllers/theme/*`), which the public layout alone loads, as CS Studio's layout alone loads `admin`: `controllers/index.js` registers neither CS Studio's controllers nor a theme's by itself, so a theme's script is never imported on a CS Studio screen, on sign-in or in setup. A controller imports `@hotwired/stimulus` and nothing a theme pinned itself: a theme adds no pin and no third-party script. The import map is read at boot, so a new controller file needs a restart in development.

## 5. Rich text (obstacle 3)

**How a text looks is entirely the theme's** (decision 12). A rendered body is plain elements under a wrapper, and the theme styles every one of them: headings (`h2` to `h4`), paragraphs, both kinds of list and their items, quotes, links, bold, italic and struck text, inline code, code blocks (`pre code`), rules, line breaks, and the two things a text can embed, an image (`figure.content-block--image` with its `img` and `figcaption`) and a video (`.content-block--youtube-embed` with `.youtube-embed__frame` and its `iframe`). `Theme::Contract::RICH_TEXT` lists these selectors, and they are part of the contract: the CMS says in its release notes when one changes. A theme reaches them three ways, and may use all three:

- the tokens the default rules read (`--th-ink`, `--th-accent`, `--th-mono`, `--th-sunken`, `--th-radius`, the type sizes), which restyle a text without a rule;
- its own CSS under its own wrapper: the Rich text block's template and the post's are the theme's (§3), so the wrapper's element and class are too, and a theme that does not write `cs-prose` on it gets none of the default rules and starts from bare elements;
- rules under `.cs-prose`, which come after the default theme's in the one stylesheet (§4) and so win.

**The one limit** (raised with the owner 2026-10-12, not yet objected to, so not confirmed): a theme does not replace the HTML structure a text is rendered to. It cannot turn a heading into another element, add a class or an attribute to one, add a node, or bring its own template for the image and the video inside a text (`RichText::ImageComponent`, `YoutubeComponent`).

The reason is that a body is rendered once and used in three places: it is cached by its document's digest and is the same HTML in CS Studio's preview, in the MCP server's Markdown round trip and on the site, so a theme inside that render would be a theme inside the editor, and every theme change would have to empty the render cache. What the documentation's design wanted beyond styling (list variants, a language on code blocks, tables: finding 6) are new things a text can SAY, which is rich-text work with its editor control and its Markdown form, listed in the roadmap entry. If the owner objects to the limit, the way in is a hook on the renderer that a theme's template fills, with the theme's fingerprint in the render cache's key; nothing in this design closes it.

## 6. The render cache (obstacle 4)

The public ETag and the rich-text render cache are keyed on `RichText.code_revision`: `KAMAL_VERSION`, else a `REVISION` file, else a random value per boot. A site image built on the same CMS image can change its theme with none of the three changing in a way that is promised.

`ThemeFolder#fingerprint` is a SHA-256 over the relative path and content of every file in the folder (`"default"` without one), computed once per boot and again on a reload in development. `PagesController` adds `Theme.current.fingerprint` to the ETag's keys. That is the whole change: the stylesheet's and the scripts' addresses are digested and printed in the page, and the rich-text cache needs nothing, because a theme styles a rendered body and does not change its HTML (§5).

What the ETag cannot see is what a template reads beyond the contract. A public page is one cookie-less answer for every visitor, so a theme's template reads the page, the tree, the site and the language, and never `params`, `request`, `cookies`, `session` or the clock; `theme:check` refuses a template that names one of the first four.

## 7. What a template may call (decision 7)

`ThemeHelper` is the contract's helper surface. Already there: `theme_site`, `translated`, `rich_text`, `render_block`, `block_outline`, `published_views`, `navigation_pages` (now memoised: the documentation theme draws the menu three times), `language_links`, `safe_social_links`, `home_url_path`, `page_url_path`, `post_url_path`, `post_date`, `resume_period`, and `public_urls.preview?`.

New, read-only:

- `page_ancestors(page)`: the pages above it, the homepage first.
- `page_section(page)`: its branch directly under the homepage; nil for the homepage.
- `page_tree(top, current: @page)`: the branch under and including `top`, to any depth, as nested nodes `title`, `path`, `children`, `current?`, `open?` (the shown page is somewhere below), `leaf?`.
- `pages_in_reading_order(node)` and `neighbouring_pages(tree, skip: nil)`: the branch flattened in tree order, and the shown page's previous and next in it.
- `with_heading_ids(html, levels: 2..3)`: the rendered blocks of a page with an id on each heading, and the headings as `id`, `text`, `level`.

The tree is read by `PublicSite::Branch` (`app/queries/public_site/branch.rb`), which returns data and knows no helper: kept and published pages only, three statements whatever the branch's size (its pages; their addresses through `PublicSite::Paths.current_paths`, which joins the reads the entry guard allows; their copies), and every title through `Publishing.published_all`, never from the rows (the spike read the rows, which would show an unpublished title in a sidebar). A page's ancestors are one statement more, and their titles come through the copies too. In a preview the rows are right, as for `published_views`. It joins the reach of `test/lib/public_readers_test.rb`, the canary and `test/integration/trash_visibility_test.rb`.

Heading ids are made on the rendered page, from each heading's text (`parameterize`, a number added when two are alike), not stored in the document: an id must be unique on the page, and a page's text is several blocks, each rendered and cached alone. The cost is one more parse of the article for a request that is not a 304, paid only by a template that calls the helper; and an id follows its heading's words, so rewording a heading breaks links to it (decision 17, accepted with that consequence). Rejected for now: a stored id on the heading node, which is a schema change in rich text, its editor and its Markdown form.

`Theme::Contract` (`app/values/theme/contract.rb`) lists the tokens (`TOKENS`), the replaceable templates with their default source (`TEMPLATES`), the replaceable components with their template methods (`COMPONENTS`, by the component's path, so the list is data and names no class), the rich-text selectors (`RICH_TEXT`) and the helpers (`HELPERS`). `theme:new`, `theme:check`, the boot check and the tests all read this one list.

## 8. Checking a folder

When the application starts (every environment but test), the boot stops with a message naming the variable and the path. It is checked in two places because the contract is application code and the folder is read before any is loaded: `ThemeFolder` refuses a path that is no directory and an unknown top-level entry while the application is configured, and `Theme.load`, in `to_prepare` (whose first run is the boot), refuses the rest against `Theme::Contract`. The boot stops when: the path is no directory; a top-level entry is not one of `views`, `components`, `assets`, `javascript`; a file under `views` or `components` is neither in the contract nor under `views/theme/`; an asset is named like one of the CMS's.

`bin/rails theme:check` does the same and also compiles every template (a syntax error names its file and line) and reads them for `params`, `request`, `cookies` and `session`. A site's image build runs it after `assets:precompile`, so a broken theme fails the build and not the site.

At a request, a template the theme does not hold is the default theme's, silently and by design. A theme's template that raises is a 500 like any template error, and the log names the theme's file.

## 9. Deployment and trust

A site's `Dockerfile` is `FROM` the CMS image, copies the theme beside the application (`/rails/site-theme`), sets `ENV THEME_PATH`, and runs `assets:precompile` and `theme:check` (the documentation repository's `hosting/Dockerfile` is this already). The CMS's image must allow that as its unprivileged user (it does: `/rails` is that user's, and the build writes only under it). CI has no Docker job and a run is billed, so CI proves the two halves that are the CMS's, the stylesheet built with `THEME_PATH` set and a production boot under the theme (`bin/theme-build-check`); the image on top is built once by hand in the plan's deployment task with the `Dockerfile` that `docs/reference/hosting.md` prints, and "As built" records it.

**No CMS image is published yet**, and publishing one is its own work. Until then a site builds the CMS image itself from the revision it pins (`contentspiel-docs/CMS_REVISION`) and builds its own on top. Nothing in this design depends on where the base image comes from.

Changing the theme of a running site is therefore a build and a deploy; in development a person edits a file in the folder and reloads the page (decision 16).

A theme is code the server runs: its templates are ERB with the application's whole reach. It is trusted exactly as the deployment is, comes only from the image, and is never uploaded, edited in CS Studio or read from the database. "No Ruby" (decision 8) is a contract about what the CMS promises to keep working, not a sandbox.

## What this does not do

New blocks (the Code block is its own pull request right after this one, decision 18; Note and Table are the catalogue's). Search. A summary field, a navigation title or "show in menus" on a page. A group heading that is not a page. A link in the menu that leaves the site. The frame option on images. The product's version in a template. A template per page type (`pages/<type>`): it belongs to page types. A theme's own HTML for rich text (decision 12's limit). Stored heading ids, list variants, a language on code blocks, tables in rich text. Appearance settings in CS Studio. Several themes in one site, or a theme chosen per page or language. A published CMS image. The content width as a token from which image `sizes` are made (a theme with another width passes its own `sizes` to `Media::PictureComponent`). A content API.

## Risks

- **ViewComponent.** Both ways of replacing a template lean on `sidecar_files`, a public class method that an upgrade could change. One test renders a block under the second theme and fails on that day.
- **The contract is a promise.** Every helper and template method on the list is one the CMS can no longer rename quietly. The list is kept short on purpose, and the reference file is checked against `Theme::Contract` so they cannot drift.
- **The public templates move.** The frame is cut out of the layout and the stylesheet is renamed; the public integration tests pin both and will need their selectors read, not just rerun.
- **Strict boot.** A stray file (`.DS_Store`, an editor's backup) would stop a site: dot files and the folder's own `README` are ignored, and nothing else.
- **A theme that reads what the ETag does not cover** serves stale pages to returning visitors. The check catches the four names; the clock and a query of its own it cannot.
- **Tailwind and paths outside the application.** `@source` and `@import` pointing out of the repository are untried in production mode; the entry file with relative paths is the plan's second proof.

## Testing

- **The second theme** is `test/fixtures/themes/plain`: plain CSS, no utilities. It replaces the frame, `pages/show`, the Rich text block's template and one post list; it changes `--th-accent`, and brings one partial under `views/theme/`, one controller, one image. It deliberately does not replace the header, the Image block or the 404, so every test of it is also a test of the fallback.
- `ThemeFolder`: unset, a missing path, an unknown top-level entry, a file outside the contract, a shadowing asset, the fingerprint (the same for the same files, another for one changed byte), the boot lines.
- `Theme#component_for`: the theme's class for a replaced template, the definition's own otherwise; the default class still renders its own template in the same process.
- Integration, with `Theme.with`: a page under the second theme has the theme's frame, the CMS's `<head>` with every tag the default has, the theme's rich-text wrapper and the default image block; the preview is drawn by it too; CS Studio is not.
- The ETag differs between two themes and between two fingerprints, and is the same for the same one.
- `PublicSite::Branch`: nesting, order, `current?` and `open?`, an unpublished page leaves with its branch, a trashed one is absent, titles are the published ones (the canary), two statements at 3 pages and at 30 (`capture_sql`).
- `neighbouring_pages` at the first and last page and with `skip:`; `with_heading_ids` for two headings alike, an empty one and text with markup.
- `Theme::Contract`: every component a type registry hands out is on the list; every token is defined in `tokens.css` (a colour for light and for dark) and no other `--th-*` is; every listed template and method exists; the default theme's CSS and templates hold no colour literal; `docs/reference/theming.md` names exactly the list.
- `theme:new` writes a folder that passes `theme:check` and draws the homepage byte for byte as the default theme does (the per-request nonce apart).
- The head: under the second theme every tag of the CMS's list is there, the title follows the theme's pattern, the icons are the theme's and its `_head` is printed; a theme folder that holds `layouts/application.html.erb` does not start.
- The stylesheet: the entry file for no theme and for the second theme (text only); one CI step (`bin/theme-build-check`) builds it with `THEME_PATH` set and finds the theme's accent and a default utility in the output, then boots production once under the theme and reads the stamp, the boot line and the theme's controller in the import map.
- `Setup::SystemCheck`: the three states of the Theme row.

## Documentation

Guide, integrators (`contentspiel-docs`, where "How to build a theme" lives; no guide text here): `theming/what-a-theme-is`, `theming/build-a-theme` (the folder, `theme:new`, `theme:check`, the Dockerfile), `theming/the-token-contract`, `theming/rendering-blocks-and-pages`, and the block and template reference, whose "what the template receives" tables are generated from `Theme::Contract`. Administrators: System status (the Theme row) and "What ContentSpiel asks of its host" (`THEME_PATH`). The documentation theme itself is updated in its repository: its layout becomes a frame, its copied tokens go, its controller becomes `theme--copy`, its own tokens leave the `--th-` prefix.

In this repository: a new `docs/reference/theming.md` (the contract, the four seams, the incidents behind the rules) with its line in `CLAUDE.md`'s index; `docs/reference/hosting.md` gains `THEME_PATH` and the image layer; `CLAUDE.md` gains the rules a change can break silently (a contract name changes only with a release note; a public reader in a theme helper goes through the published copy; nothing of a theme reaches CS Studio; the theme's fingerprint stays in the ETag).

## As built

Built 2026-10-12 on the branch `theming`. Where the code departed from the sections above, and why. The description of what is there now is `docs/reference/theming.md` (and `docs/reference/hosting.md` for what a host meets); where this section and a section above differ, this one is what was built.

1. **The generated subclass was built; the fallback was not taken** (§3, decision 9). `Class.new(component)` with its own `sidecar_files` passed the first task's test unchanged against view_component 4.15.0. The subclass has three things to say because it is anonymous: `name` (the gem calls `name.underscore`), `virtual_path` and `identifier` (both derived at a moment the class has no name, the second from the call stack). The spike's override of `ApplicationComponent.sidecar_files` is in no file.
2. **The entry file imports the default theme's file; the second proof held, and two lines were added to it** (§4). Tailwind built an entry whose `@import` and `@source` point outside the repository (the one class used only in the outside template was in the output, and absent from a control build without the `@source`). Both imports come before the `@source` lines. Added: an `@source` for each folder a stylesheet is imported from (the default theme's, and the theme's `assets/stylesheets`). They add nothing to the build (byte for byte the same output) and are there for the watch: Tailwind's watcher watches the entry's own folder and the folders its `@source` lines name, never the folder of an imported file, so with the entry in `tmp/theme` a change to `tokens.css` or to a theme's `theme.css` was rebuilt by nobody. And the theme is named by its real path, because the watcher reports changed files by real path and a theme reached through a link was built once and never again.
3. **The stamp is `app/assets/builds/.theme.stamp`, not `theme.stamp`** (§4). `app/assets/builds` is on Propshaft's load path: the file without the dot was an asset, copied to `public/assets`, listed in the manifest and served. Propshaft leaves dot files out.
4. **The stamp vouches for a build that succeeded, and is the fingerprint read before the build** (§4). It is taken away before the executable starts and written after it ended well, so a failed build leaves none, an earlier one's included. The boot and System status therefore have a second sentence, for no stamp at all: nothing "was built for another theme" in a fresh checkout or after a failed build.
5. **The watch is a loop, and it builds beside Tailwind's watcher** (§4, "In development `theme_css:watch` … watches the same entry"). Tailwind's watcher, started on an entry that does not build, prints the error and exits, and Foreman then stops the web server with it: a person with a half-written `@import` could not start the application. `ThemeCss.watch` builds, starts the watcher, and on a failure says one line and waits for a file to change. A keeper thread beside the watcher builds once more itself, quietly, on each change of the theme's folder, because nobody hears whether the watcher's own rebuild succeeded and the stamp must follow the folder's fingerprint or System status would warn after the first edit.
6. **System status asks the stamp in every environment, with wording per environment** (§1 said "a warning when a theme is set in production"). In production the boot already refuses the mismatch, so the warning matters most where nothing refuses: in development, where a test run rebuilds the default theme's stylesheet into the place the development server reads. The row has three states (OK, another theme's stamp, no stamp) and offers `bin/rails tailwindcss:build` outside production.
7. **Development and test share the built stylesheet and its entry.** Not designed, found: `bin/rails test` builds the default theme's stylesheet under a running `bin/dev`. Said by System status and by the test build itself; an output per environment was ruled too large for this work and is on the roadmap.
8. **The boot line carries the `[ContentSpiel]` prefix, is logged in development too, and has a third wording** (§1): a folder that holds no file of a theme says that it replaces nothing.
9. **System status names the folder and not its path** (§1, "the same fact"), and eight characters of the fingerprint: the page is shown to anyone who may view it.
10. **`ThemeFolder` checks more than the path and the top-level entries** (§8): every file must be readable, a link may not leave the folder, name nothing or name a folder it is in, and a dot directory below the top is refused. A theme reaches a container as one copied folder and must be whole; an unreadable folder was skipped in silence by a glob. Every stranger at the top is said in one refusal. And every message says what to do, which the spec's did not.
11. **The check reads template sources at boot, not only names** (§8 had only `theme:check` reading templates): a head tag of the CMS's printed by a theme, the CSRF token asked for, a form sent with a token, a write to the head's slot, an assignment to an instance variable, a frame that never yields and a title pattern that prints nothing all stop the boot. The files are read once for the fingerprint anyway, and the CSRF case is the one that matters in production.
12. **Assets are taken by extension** (§4 said only "a file named like one the CMS ships stops the boot"). A folder on the load path is served whole, so `assets/images` takes eight image extensions and `assets/fonts` four font extensions and nothing else. Two files of one theme can then never share a served name, and that half of the shadowing rule went.
13. **The CMS's asset roots are a list plus the gems', and never the theme's own folders** (§4). The first version took every root of the load path outside the application for a gem's; a real theme is outside the application and its own folders are on that path, so no site with a theme of its own started, while every test was green because the fixture theme is inside the application. Since then the boot test and `bin/theme-build-check` copy the theme outside first.
14. **The fence is read with Ruby's own lexer, per ERB tag, and misses on purpose** (§6, §8: "reads them for `params`, `request`, `cookies` and `session`"). Two rounds of patterns over the source turned inside out on a string holding ` #` and refused `link_to "Our cookies", "/cookies"` at a site's build. `Ripper.lex` tells code, strings and comments apart. `flash` is a fifth name. A name the template binds itself (a block parameter named `session`) is the theme's own and is let through, and a tag is read both ways where Ruby's reading depends on whether a name is a local: the deep check gates a build, so it lets through where it is unsure. The reference file lists what it misses. It is a fence against mistakes and not a sandbox, and the code and its messages say so.
15. **`theme:check` starts the application itself, and runs BEFORE `assets:precompile`** (§8 and §9 had it after, as a task that depends on the environment). Under a `THEME_PATH` the contract refuses the application does not start, so as a prerequisite the boot ended the command with a trace and the boot's half of the list, and the deep half came to light one build later. The task now starts the application inside `ThemeFolder.checking`, in which a refusal is kept and not raised, and prints every problem as a numbered line. In a site's Dockerfile the check goes first for the same reason: `assets:precompile` under a refused folder ends in rake's trace. Both commands carry `SECRET_KEY_BASE_DUMMY=1`.
16. **`theme:new` and `theme:check` take the path as a rake argument** (`bin/rails 'theme:new[PATH]'`), with `THEME_NEW_PATH` and `THEME_PATH` for a path with a comma in it, which rake cuts an argument at. `theme:new` writes into a folder that holds only a repository, dot files and a README, and prints its next step quoted for a shell. The compile error is one sentence worded from Prism's first error, with cases of its own for a block never closed and for one `end` too many.
17. **A theme refused on a development reload does not raise** (§8, "the boot stops"). At boot it does. On a reload a raise in the prepare chain left the type registries empty and the next request drawn by the default theme with no block types, so the refusal is kept and every public page raises it until the folder is sound; CS Studio keeps working.
18. **The `site` entry point** (§4, as corrected before the build): a theme's controllers are registered by a third entry point, because `application` is also what sign-in and setup load.
19. **The head: the layout reads no slot, and a 404 is told by the response's status** (§2). `content_for(:title)` and `content_for(:head)` are not read on the public side, because `content_for` appends and the page is rendered before the layout: a theme's template that wrote to either put its text in front of the title or its tags among the CMS's. And moving `pages/_seo_meta` into the layout removed what had kept it off a 404: a 404 can have a page and a post in hand, and such a 404 printed the post's title and the listing page's description. The layout asks `page_found?`; a 404 has the site's title and no description, Open Graph tag, canonical link or language link. The canonical and language links on such a 404 were older than this work and were closed with it. The three "installable app" metas moved after the language links.
20. **The 404's title is the site's title through the theme's pattern** (§2 names it): it was the literal "ContentSpiel".
21. **The public site commits no session and mints no token, as a wall** (§2 had "no CSRF token on a public page" as a decision). Three lines of `PublicController`: the session is skipped, `protect_against_forgery?` is false, `form_authenticity_token` is nil. With forgery protection on, a theme's `form_with` set a real session cookie on a publicly cacheable page. This changes every public request, theme or not; nothing read a session there. A later feature that wants a public cookie meets it first.
22. **"The content security policy is the CMS's" promises more than exists** (§2). The policy sets `frame-src`, `object-src` and `base-uri` only. A second stylesheet link is refused by the folder check (decision 11), a script or an `@import` from another host by nothing. On the roadmap.
23. **Struck text reaches the public page** (§5 lists "struck text"). The scrubber's list had `del` and no `s`, so the editor showed a text struck and the site did not. The contract's test of what a text is made of found it; `s` was added, in a commit of its own. It changes what a visitor sees of existing struck text, after a deploy.
24. **The helpers hand a template value objects, never pages** (§7). `page_ancestors` and `page_section` first answered pages, from which a template can walk rows no guard reads. They answer `PublicSite::Branch::Node` now, which also has `id`, `subtitle`, `slug`, `depth` and `reading_order` beside the fields §7 names; `page_section` answers the section's whole tree with the page marked, so `page_tree(page_section(@page))` reads nothing more. `Branch` answers `under(top, current:)` and `around(page)`, not `tree` and `ancestors`.
25. **`page_found?` joined the contract, and every helper answers empty on a 404 and with no page** (§7). A frame could otherwise only ask `response.not_found?`, which is not on the contract, and a 404 with a page in hand drew the section's tree.
26. **A branch costs four statements, three for the homepage; a page drawing tree, crumbs and neighbours costs four in all** (§7 says three, and "one statement more" for the ancestors; "Testing" says two). `depth` counts from the homepage, which is the statement for the pages above the top; the ancestors come from the same statements, with none per ancestor.
27. **Heading ids keep the letters of every script, drop what nobody sees, and bound the article** (§7: "`parameterize`, a number added when two are alike"). `parameterize` empties a Greek, Arabic or Japanese heading, so a page in one of them would have got ids that follow a heading's place and move when one is added above: worse than the consequence decision 17 accepted. Latin text is what `parameterize` answers; other scripts keep their words. Invisible characters (joiners, variation selectors, a keycap's mark) are dropped, a heading with no letter or digit is `section`, a line break is a space, an id a heading already has is kept. A heading inside `nav`, `aside`, `header`, `footer`, a list item or a link is not the article's and gets no id and no entry. What is not html-safe is escaped first.
28. **In the preview of a draft page the tree, crumbs and neighbours hold published pages only** (§7, "in a preview the rows are right", which is true of titles). Not decided; put to the owner and on the roadmap.
29. **Seven production boots** (`test/lib/production_boot_test.rb`; three before this work, five after the third task): a folder outside the application, a path that is no folder, a folder with a file the contract does not name, and, the one boot with a real secret, a stylesheet not built for the theme.
30. **CI builds no image; the site's image was built by hand, twice, and drew a public page** (§9). On macOS (arm64, OrbStack), plain `docker build`, nothing pushed. The CMS image, then a site image from the five lines `docs/reference/hosting.md` prints, with the second theme and a font added. Seen: the build runs as the image's unprivileged user; `public/assets` holds the digested stylesheet with the theme's image and font at digested addresses in it, and the theme's controller; the stamp is in the image, equals the fingerprint computed on the laptop, and is no asset; production starts under the theme and refuses with the stamp removed and with `THEME_PATH` emptied; `theme:check` in the finished image says "9 templates, no problems". Then, with a throwaway Postgres container on a private Docker network and the image's own entrypoint and command: `db:prepare` created the four databases, the starter content was written by the code the wizard's last step runs, and `/` was 200, drawn by the theme's frame, page template and block template with the CMS's canonical link, CSP tag and import map once each and no `Set-Cookie`; a second request was 304, `/up` 200, a missing page 404 inside the theme's frame with no canonical link, a foreign `Host` 403. Everything made was removed by name. What it found: the image reaches its four databases only through libpq's `PGHOST` (`config/database.yml` names no host), which is hosting's part three.
31. **Decision 12's limit is still unconfirmed.** Built on as written.

Test names of "Testing" that read differently in the code: "two statements at 3 pages and at 30" is "a branch costs four statements at 4 pages and at 30, the homepage's three, and what is around a page four with none per page above"; "`ThemeFolder`: … a file outside the contract, a shadowing asset" are `Theme::Check`'s tests (`test/values/theme/check_test.rb`), since the contract is checked there; "`docs/reference/theming.md` names exactly the list" is `test/lib/theming_reference_test.rb`, five tables; "`Setup::SystemCheck`: the three states" are six tests, a state having a wording per environment; and the second theme also replaces `_title`, `_icons` and `_head`, and brings two partials.
