# Changelog

## Unreleased

### Theme contract

- Added `theme.yml` at a theme folder's top, the one file beside its four folders: the lists `section_styles`, `page_templates` and `icons`, each entry a `name` (lowercase letters, digits and underscores, a letter first, at most 40) and a `label` (a text, or a mapping of language codes to texts), a page template also its `fields` (today only `hero`), an icon its `file` (an SVG under `assets/images`). A list the file does not declare is the default theme's; `page_templates: []` is refused. Any other list, any other key, and `settings` ("Appearance settings are not built yet.") stop the boot.
- Added page templates: `views/pages/templates/_<name>.html.erb`, one per entry of `page_templates`, rendered by `pages/show` with the locals `page`, `post` and `list_block` and nothing else. The default theme's are `standard` and `landing`, drawing what the page types drew. `theme:check` refuses `@page`, `@post` and `@post_list_block` in a page template.
- Added the helper `page_template`: the name of the template drawing the shown page (its stored one while the theme declares it, else the theme's first).
- The Section's template may call `style` and `anchor` (its line is now `block page columns layout background width style anchor`). The default template writes the class `content-section--style-<name>` for a style the theme declares, and the anchor as the section's `id`; a heading whose id would equal an anchor of the page gets a suffix.
- Added the Card block's component line: `block page title text link icon icon_name`.
- Added the Card's three tokens, `--th-card-ground`, `--th-card-line` and `--th-card-icon` (themed: a light and a dark value, re-valued in a strong band). The token names are the promise, not today's values.
- Added the default theme's icon names: `arrow_right`, `check`, `star`, `heart`, `mail`, `map_pin`, `calendar`, `user`, `shield`, `briefcase`, `clock`, `globe` (Lucide outlines; underscores where Lucide has a hyphen).
- An icon file is checked by a fence when the application starts: at most 32 KB, well-formed SVG, SVG's drawing elements only, no `script`, `foreignObject` or `style` element, no `style` or `on…` attribute, no address but `#…`, no `DOCTYPE` or entity, and no `id`.
- Added the attributes `img[data-image-preview]` and `img[data-image-empty]`, the two loading states of a library image's `<img>`, as names a theme's stylesheet may select.
- `theme:new` also writes a `theme.yml` of comments only and copies the two page templates.

### Environment

- None.

### Migrations needing action

- None beyond `db:migrate`. `20261101100000_replace_page_type_with_page_settings` moves every page's type into `pages.settings` and rewrites every page's published copies (current, pending and superseded) the same way; nothing is drawn differently and the content version does not move. A unique index on a section's anchor is added (no anchor exists before it).

### Removed

- `Page#page_type` and `Page#landing?`, and the `page_type` column: a template writes `page_template == "landing"`. `theme:check` refuses a call of either with that sentence.
