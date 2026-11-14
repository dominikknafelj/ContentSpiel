# THE LEDGER (block types spec, decision 4). The contract's block lists are
# derived from the registry, which makes ADDING a name easy and also makes
# REMOVING one easy: a method dropped from a type's `theme_methods`, a token
# renamed, a type deleted, and a theme outside this repository breaks with no
# test failing. This is the one hand list kept on purpose: the built-in
# types' part of the contract, written out, held to the code by
# test/values/theme/contract_ledger_test.rb and to docs/reference/theming.md
# by test/lib/theming_reference_test.rb. Changing it is the moment a person
# writes the release note ("a name added, renamed or removed is a release
# note"), so change it only together with that note.
#
# A type with an owner's name (`gallery/album`, `test/quote`) is its gem's
# promise, not the CMS's, and is not in it.
module ContractLedger
  COMPONENTS = {
    "blocks/rich_text_component" => %w[block page],
    "blocks/image_component" => %w[block page asset alt caption sizes],
    "blocks/code_component" => %w[block page lines code language language_label filename caption string],
    # Release note (diagram): added the Diagram block's line, its thirteen
    # themed tokens and its fixed font below (docs/reference/theming.md,
    # "The Diagram block").
    "blocks/diagram_component" => %w[block page svg description caption],
    "blocks/note_component" => %w[block page kind heading titled? word icon body],
    "blocks/table_component" => %w[block page rows header_row? header_column? column_count caption],
    # Release note (forms): added the Form block, its line and the five
    # inputs it draws through the theme, each called with the field, the
    # typed value and the error (`Theme::Contract::FORM_INPUT_METHODS`);
    # six themed tokens below; and the markup the `form-send` script reads
    # (docs/reference/theming.md, "The Form block").
    "blocks/form_component" => %w[block page form_name fields action locale page_id drawn honeypot submit_label thank_you unavailable string],
    "blocks/card_component" => %w[block page title text link icon icon_name image],
    "blocks/post_list_component" => %w[block page list_component],
    "blocks/section_component" => %w[block page columns layout background width style anchor],
    "blocks/form_fields/short_text_component" => %w[field value error],
    "blocks/form_fields/long_text_component" => %w[field value error],
    "blocks/form_fields/email_component" => %w[field value error],
    "blocks/form_fields/choice_component" => %w[field value error],
    "blocks/form_fields/checkbox_component" => %w[field value error],
    "posts/blog_list_component" => %w[posts page],
    "posts/resume_list_component" => %w[posts page],
    "posts/now_list_component" => %w[posts page],
    "posts/detail_component" => %w[post]
  }.freeze

  # The classes a theme's stylesheet may rely on that a template of the CMS
  # writes from a choice of the theme's own (`Theme::Contract::CLASSES`).
  CLASSES = {
    "content-section--style-<name>" => "on the section, for a style the theme declares"
  }.freeze

  # The attributes a theme's stylesheet may select that a CMS template
  # writes: a library image's two loading states (`Theme::Contract::ATTRIBUTES`).
  ATTRIBUTES = {
    "img[data-image-preview]" => "an image whose widths are not made yet: `src` is its ~24px preview",
    "img[data-image-empty]" => "an image with neither widths nor a preview: no `src`, a box of the image's size"
  }.freeze

  # The locals every page template is handed, and the folder of the templates
  # (`Theme::Contract::PAGE_TEMPLATE_LOCALS`, `PAGE_TEMPLATES`).
  PAGE_TEMPLATE_LOCALS = %w[page post list_block].freeze
  PAGE_TEMPLATES = "pages/templates/".freeze

  THEMED_TOKENS = %w[
    paper surface sunken ink dim meta line line-strong
    accent accent-hover accent-tint on-accent
    ok ok-ink ok-tint warn warn-ink warn-tint danger danger-ink danger-tint
    shadow-menu
    band-tinted band-strong on-band-strong on-band-strong-dim on-band-strong-accent
    syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed
    diagram-ink diagram-fill diagram-line diagram-edge diagram-group diagram-note diagram-accent
    diagram-series-1 diagram-series-2 diagram-series-3 diagram-series-4 diagram-series-5 diagram-series-6
    note-note-ground note-note-line note-note-ink note-note-border
    note-tip-ground note-tip-line note-tip-ink note-tip-border
    note-important-ground note-important-line note-important-ink note-important-border
    note-warning-ground note-warning-line note-warning-ink note-warning-border
    table-rule table-line table-head table-caption table-ground
    form-field-ground form-field-line form-field-focus form-error form-done-ground form-done-line
    card-ground card-line card-icon
  ].freeze

  FIXED_TOKENS = %w[
    font mono
    t-display t-h1 t-h2 t-h3 t-body t-small t-label
    track-mono track-wide
    sp-1 sp-2 sp-3 sp-4 sp-5 sp-6 sp-7
    radius radius-pill ease
    diagram-font
  ].freeze

  # The default theme's icon names (a promise: a theme outside this
  # repository may store one, and a card keeps drawing it).
  DEFAULT_ICONS = %w[arrow_right check star heart mail map_pin calendar user shield briefcase clock globe].freeze
end
