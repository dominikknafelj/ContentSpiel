require "test_helper"

# The Search block's type (search spec §7.1): a field for the visitors of a
# page, its one value the label, translated; the request's search is handed
# to it because it claims `:search`.
class BlockTypes::SearchTest < ActiveSupport::TestCase
  include ContentHelper

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
    assert_equal %w[block page label query state results total pagination action live_note? close_matches? correction correction_path suggest_url string],
      definition.theme_methods
    assert_equal %w[search-mark search-mark-ink search-active], definition.themed_tokens
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

  # CS Studio: the label's placeholder is the visitor's word, its help a key
  # that names it, and the card's note a key of the card's own.
  test "the label shows the visitor's word as its placeholder, its help and the card's note are keys" do
    definition = BlockTypes.fetch(:search)
    label = definition.fields.sole

    assert_equal "blocks.search.label", label.options[:placeholder_public]
    assert_equal :"search.label_help", label.help
    assert_equal :"search.note", definition.editor_note
  end

  test "placeholder_public is refused on a field that is not a string" do
    %i[text integer boolean].each do |type|
      error = assert_raises(ArgumentError, type.to_s) do
        BlockTypes.register(:test_search_like) do |t|
          TestTypes.declare(t)
          t.field :label, type, placeholder_public: "blocks.search.label"
        end
      end
      assert_includes error.message, "placeholder_public"
    end
  ensure
    Rails.application.reloader.prepare!
  end

  def search_block(label = nil, locale: "en")
    @search_pages = (@search_pages || 0) + 1
    page = create_page(title: "Find #{@search_pages}")
    block = page.content_blocks.new(block_type: "search", position: 0)
    block.assign_settings({ "label" => label }, locale: locale) if label
    block.save!
    block
  end

  # The tile is never "Empty": a blank label draws the CMS's own word.
  test "the tile's heading is the label, or the visitor's word standing quiet, and its line says what is searched" do
    filled = search_block("Search the guide")
    assert_equal [ [ :hint, :searches_live ] ], BlockTypes::Search.summary(filled, locale: "en")
    preview = BlockTypes::Search.preview(filled, locale: "en")
    assert_equal "Search the guide", preview.heading
    assert_not preview.quiet_heading
    assert preview.line

    blank = search_block
    assert_equal [ [ :hint, :default_label ], [ :text, " · " ], [ :hint, :searches_live ] ], BlockTypes::Search.summary(blank, locale: "en")
    preview = BlockTypes::Search.preview(blank, locale: "en")
    assert_equal "Search this site", preview.heading
    assert preview.quiet_heading
    assert preview.line
  end

  # The tile says what a visitor of the language shown reads: a label of
  # the default language along the fallback, else the visitor's word in
  # that language.
  test "the tile reads the label along the site's fallback and the visitor's word in the language shown" do
    with_locales(%w[en de], default: "en") do
      english = search_block("Search the guide")
      preview = BlockTypes::Search.preview(english, locale: "de")
      assert_equal "Search the guide", preview.heading
      assert_not preview.quiet_heading
      assert_equal [ [ :hint, :searches_live ] ], BlockTypes::Search.summary(english, locale: "de")

      I18n.backend.store_translations(:de, public: { blocks: { search: { label: "Diese Website durchsuchen" } } })
      blank = search_block
      assert_equal "Diese Website durchsuchen", BlockTypes::Search.preview(blank, locale: "de").heading
      assert_equal "Search this site", BlockTypes::Search.preview(blank, locale: "en").heading
    end
  ensure
    I18n.reload!
  end
end
