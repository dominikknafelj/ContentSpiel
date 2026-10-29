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
    "blocks/note_component" => %w[block page kind heading titled? word icon body],
    "blocks/table_component" => %w[block page rows header_row? header_column? column_count caption],
    "blocks/post_list_component" => %w[block page list_component],
    "blocks/section_component" => %w[block page columns layout background width],
    "posts/blog_list_component" => %w[posts page],
    "posts/resume_list_component" => %w[posts page],
    "posts/now_list_component" => %w[posts page],
    "posts/detail_component" => %w[post]
  }.freeze

  THEMED_TOKENS = %w[
    paper surface sunken ink dim meta line line-strong
    accent accent-hover accent-tint on-accent
    ok ok-ink ok-tint warn warn-ink warn-tint danger danger-ink danger-tint
    shadow-menu
    band-tinted band-strong on-band-strong on-band-strong-dim on-band-strong-accent
    syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed
    note-note-ground note-note-line note-note-ink note-note-border
    note-tip-ground note-tip-line note-tip-ink note-tip-border
    note-important-ground note-important-line note-important-ink note-important-border
    note-warning-ground note-warning-line note-warning-ink note-warning-border
    table-rule table-line table-head table-caption table-ground
  ].freeze

  FIXED_TOKENS = %w[
    font mono
    t-display t-h1 t-h2 t-h3 t-body t-small t-label
    track-mono track-wide
    sp-1 sp-2 sp-3 sp-4 sp-5 sp-6 sp-7
    radius radius-pill ease
  ].freeze
end
