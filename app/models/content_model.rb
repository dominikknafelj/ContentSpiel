# The content model's seams to the application above it. A field of type
# `:theme_choice` names an entry of one of the lists the theme declares in
# theme.yml, and the content model sits below the theme (CLAUDE.md,
# Dependency order), so the list comes in as a callable, as
# `RichText.component_renderer` does.
module ContentModel
  class NoThemeChoices < StandardError; end

  class << self
    attr_writer :theme_choices, :link_target_readable

    # `->(reference) { truthy when the acting person may read its target }`,
    # for a `:link` field's new reference, assigned in
    # `config/initializers/types.rb`: the content model sits below the access
    # rules and the records.
    def link_target_readable
      @link_target_readable || raise(ArgumentError, "ContentModel.link_target_readable is not set: config/initializers/types.rb assigns it in to_prepare")
    end

    # `->(list) { Array of objects answering name and label_for(locale) }`,
    # assigned in `config/initializers/types.rb`. Asked at each validation
    # and each draw, never kept, so a theme swapped afterwards is seen.
    def theme_choices
      @theme_choices || raise(NoThemeChoices,
        "ContentModel.theme_choices is not set: config/initializers/types.rb assigns it in to_prepare. " \
        "Outside the app, assign a callable that takes a list name and returns its entries: " \
        "ContentModel.theme_choices = ->(list) { [] }")
    end
  end
end
