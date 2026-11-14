require "test_helper"

# The Search block's type (search spec §7.1): a field for the visitors of a
# page, its one value the label, translated; the request's search is handed
# to it because it claims `:search`.
class BlockTypes::SearchTest < ActiveSupport::TestCase
  test "Search is a form-family block with a translated label and the :search capability" do
    definition = BlockTypes.fetch(:search)

    assert_equal "Search", definition.label
    assert_equal "search", definition.icon
    assert_equal :form, definition.family
    assert_equal [ %w[label string] ], definition.fields.map { |field| [ field.name, field.type.to_s ] }
    label = definition.fields.first
    assert label.translated?, "the label is the visitors' language"
    assert_not label.required?, "a blank label draws the CMS's own word"
    assert_equal 80, label.options[:max]
    assert definition.capability?(:search)
    assert_not definition.capability?(:container)
    assert_equal Blocks::SearchComponent, definition.component
    assert_equal %w[block page label query state results total pagination action live_note? string], definition.theme_methods
    assert_equal %w[search-mark search-mark-ink], definition.themed_tokens
    assert_empty definition.fixed_tokens
    assert_equal Rails.root.join("app/assets/tailwind/themes/default/search.css"), definition.stylesheet_path
    assert_equal [ "Search the guide" ], definition.sample.shows
    assert_equal({ label: "Search the guide" }, definition.sample.translations.fetch("en"))
  end

  test "it declares no searchable text" do
    assert_empty BlockTypes.fetch(:search).search_texts, "the block is a field, not content"
  end

  test "the Search block stands after the Form in the picker" do
    names = BlockTypes.built_in_names
    assert_equal names.index("form") + 1, names.index("search")
  end
end
