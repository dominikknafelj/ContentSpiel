# Changelog

## Unreleased

### Theme contract

- Added `theme.yml` at a theme folder's top, the one file beside its four folders: the lists `section_styles`, `page_templates` and `icons`, each entry a `name` (lowercase letters, digits and underscores, a letter first, at most 40) and a `label` (a text, or a mapping of language codes to texts), a page template also its `fields` (today only `hero`), an icon its `file` (an SVG under `assets/images`). A list the file does not declare is the default theme's; `page_templates: []` is refused. Any other list, any other key, and `settings` ("Appearance settings are not built yet.") stop the boot.
- Added page templates: `views/pages/templates/_<name>.html.erb`, one per entry of `page_templates`, rendered by `pages/show` with the locals `page`, `post` and `list_block` and nothing else. The default theme's are `standard` and `landing`, drawing what the page types drew. `theme:check` refuses `@page`, `@post` and `@post_list_block` in a page template.
- Added the helper `page_template`: the name of the template drawing the shown page (its stored one while the theme declares it, else the theme's first).
- The Section's template may call `style` and `anchor` (its line is now `block page columns layout background width style anchor`). The default template writes the class `content-section--style-<name>` for a style the theme declares, and the anchor as the section's `id`; a heading whose id would equal an anchor of the page gets a suffix.
- Added the Card block's component line: `block page title text link icon icon_name`. `link` is an `http`, `https` or `mailto` address, a site-relative one or a same-page anchor (`#team`).
- The Card's line is now `block page title text link icon icon_name image`. `image` is nil for a card with no image, and otherwise what `Media::PictureComponent` takes, a Hash of `asset`, `alt` and `sizes`: `<%= render Media::PictureComponent.new(**image, css_class: "…") if image %>`. A theme's Card template without it keeps working and draws no image. **A card with an image and no words is now drawn**: a template can now meet a card with no title or text and must guard them, and it draws its frame empty until it draws `image`. With no title and no text the default template puts the link on the image, whose alt then names it; a theme does the same, so a card stays one link.
- For a gem's block type: `t.icon "name", family: :text` (one of `text media code form lists structure`) names the hue of the chip CS Studio draws the icon on; a type that names none is drawn on the neutral chip, and any other value is refused at registration. Nothing a visitor sees changes.
- For a gem's block type: a type with `uses :image` and a `summary` of its own no longer gets the tile's missing-image mark, and an image leads the block's form only where the type has fields.
- The Card's `link` also answers for a card linked to a page or a post, as that target's current address in the visitor's language, or nil while a visitor can't reach it. It is still an address or nil, so a template needs no change. A template that reads the stored value through `block` instead will find `cs:page/12` where it may have found an address: use `link`.
- Added the Card's three tokens, `--th-card-ground`, `--th-card-line` and `--th-card-icon` (themed: a light and a dark value, re-valued in a strong band). The token names are the promise, not today's values.
- Added the default theme's icon names: `arrow_right`, `check`, `star`, `heart`, `mail`, `map_pin`, `calendar`, `user`, `shield`, `briefcase`, `clock`, `globe` (Lucide outlines; underscores where Lucide has a hyphen).
- An icon file is checked by a fence when the application starts: at most 32 KB, well-formed SVG, SVG's drawing elements only, no `script`, `foreignObject` or `style` element, no `style` or `on…` attribute, no address but `#…`, no `DOCTYPE` or entity, and no `id`.
- Added the attributes `img[data-image-preview]` and `img[data-image-empty]`, the two loading states of a library image's `<img>`, as names a theme's stylesheet may select.
- `theme:new` also writes a `theme.yml` of comments only and copies the two page templates.
- Added the Form block: `blocks/form_component` with thirteen names (`block page form_name fields action locale page_id drawn honeypot submit_label thank_you unavailable string`), and the five inputs it draws through the theme, each its own line with `field`, `value` and `error`: `blocks/form_fields/short_text_component`, `long_text_component`, `email_component`, `choice_component` and `checkbox_component`. `string` answers six keys (`required`, `choose`, `sending`, `sent`, `error_summary` with `count:`, `network`) and no other.
- Added six themed tokens: `--th-form-field-ground`, `--th-form-field-line`, `--th-form-field-focus`, `--th-form-error`, `--th-form-done-ground` and `--th-form-done-line` (a light and a dark value, re-valued in a strong band).
- Added the markup the `form-send` script reads, a promise to a theme's Form template: `data-controller="form-send"` and `data-action="form-send#send"` on the `<form>`, with `data-turbo="false"`; the hidden inputs `locale`, `page_id` and `drawn`; the targets `summary`, `body`, `button`, `status` (optional) and `done`; the values `sending`, `network` and `fields`; and, optional, `data-action="click->form-send#follow"` on the summary. A template without it still posts to the endpoint and lands on its plain page.
- A public page's ETag now also names whether the site has Active Record encryption keys, which decide whether its forms take answers.
- A link to an anchor of the same page (the same origin, path and query, with a fragment) is now the browser's on every public page, not a Turbo visit: the page is not drawn again, so what a theme's script wrote into it stays. Another page, or the same path with another query, is still a visit.

### Environment

- A form's submission mail is in no log at any level: at `RAILS_LOG_LEVEL=debug` Action Mailer's line for it is a placeholder, where every other mail is still logged whole.
- A new recurring task, `forms_resend_not_ready` (every 15 minutes, in `config/recurring.yml` for every environment): once mail is set up, by Settings or by `MAIL_*` variables, the form mails that failed because it was not are sent again, each recorded as System's "sent a submission again".

### Migrations needing action

- `db:migrate` adds the forms' four tables (`forms`, `form_destinations`, `form_submissions`, `form_deliveries`) and `site_settings.form_keep_days` (90), and `20261104090300_grant_forms_permissions_to_admin_group` gives the built-in Admin group "Manage forms" and "View form submissions"; any other group gets them by hand on the Groups screen.
- **A site without Active Record encryption keys takes no form answers**: every form says it can't take answers, a send is refused, and System status's Forms row says so. Set the three keys (`docs/reference/translations.md`, "Active Record encryption keys") before placing a form.
- A site behind a CDN adds the CDN's ranges to `config.action_dispatch.trusted_proxies`, or the forms' per-visitor rate limit counts every visitor as one (`docs/reference/hosting.md`, "Forms").
- None beyond `db:migrate`. `20261101100000_replace_page_type_with_page_settings` moves every page's type into `pages.settings` and rewrites every page's published copies (current, pending and superseded) the same way; nothing is drawn differently and the content version does not move. A unique index on a section's anchor is added (no anchor exists before it).

### Removed

- `Page#page_type` and `Page#landing?`, and the `page_type` column: a template writes `page_template == "landing"`. `theme:check` refuses a call of either with that sentence.

### For a gem or an outside caller

- Added two hooks beside `ContentSpiel::Plugins.block_types`: `form_field_types` (a form field type's members, `owner/name`) and `form_destinations` (a destination's label, deliverer and settings block, `owner/name`), with the block types' owner rules and replayed after them (`docs/reference/content-blocks-and-types.md`, "Form field types and destinations from outside"). A destination's deliverer answers `deliver(delivery, final_attempt:)`.
- `AccessControl::Permissions.register` takes `grantable:` (default true); `Permissions.grantable` is what a group may hold. A caller that listed `Permissions.all` to offer or seed grants now reads `grantable`.
- `ContentModel::FieldTypes` has two more built-ins, `email` and `form`, and `text` takes `max:`.
- A form field type or destination that a gem no longer registers is dormant, not gone: a stored field of it is left out of a send and carried through a save, and a stored destination of it is carried through a save (its deliveries fail `unknown_destination`) and drawn in the builder with a box that removes it. Only one given anew under an unknown name is refused.
- `Posts::Save` and `Pages::Save` refuse a key under a language they would drop, by name, writing and auditing nothing, as `ContentBlocks::Save` does (#147). A caller outside this repository that sent such a key gets a failed result where it got ok.
