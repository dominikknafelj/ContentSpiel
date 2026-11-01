# Changelog

## Unreleased

### Theme contract

- Added `theme.yml` at a theme folder's top: the lists `section_styles`, `page_templates` and `icons`.
- The Section's template may call `style`; the default template writes `content-section--style-<name>`.
- Added the helper `page_template`.
- Added `views/pages/templates/_<name>.html.erb` and its locals `page`, `post`, `list_block`.

### Environment

### Migrations needing action

- None beyond `db:migrate`; it rewrites every page's published copies.

### Removed

- `Page#page_type` and `Page#landing?`: a template writes `page_template == "landing"`.
