require "test_helper"

# THE DERIVED PUBLIC SMOKE TEST (block types spec, "New guards"): every
# registered block type's sample saves, publishes and draws its words, at the
# top level and in a column, and the page draws them from the published copy.
# A type joins this by declaring its sample; nobody writes a row for it.
# `test/quote` (test/support/test_types.rb) is registered too, so the test
# also runs a type with an owner's name.
class BlockSamplesTest < ActionDispatch::IntegrationTest
  include EveryBlockType

  CANARY = "SAMPLE-CANARY-41d0".freeze

  # The schema fields a sample may leave empty, by type, each with the reason
  # another test compares it instead. Every other non-group field of a sampled
  # type is filled, because the canary overwrites only the values a block
  # holds: a field the sample leaves out is never compared with the rows.
  UNFILLED_FIELDS = {
    "post_list" => { "tag" => "a listing filtered by a tag is the canary's own row on Alpha (\"tag\" => \"ruby\"), which also lists a tagged post" }
  }.freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    create_post(title: "A listed post")
  end

  def path_of(page) = PublicSite::Urls.new.path_for(page.reload, "en")

  def main_of(body) = Nokogiri::HTML5(body).at_css("main")

  def assert_shows_drawn(body, where)
    main = main_of(body)
    top = main.dup
    top.css(".content-section").each(&:remove)
    sampled_types.each do |definition|
      definition.sample.shows.each { |text| assert_includes top.to_html, text, "#{definition.name}'s sample draws #{text.inspect} at the top level #{where}" }
    end
    return if sampled_types.none? { |definition| definition.capability?(:container) }

    column = main.css(".content-section__column").first&.to_html.to_s
    sampled_types.reject { |definition| definition.capability?(:container) }.each do |definition|
      definition.sample.shows.each { |text| assert_includes column, text, "#{definition.name}'s sample draws #{text.inspect} in a column #{where}" }
    end
  end

  test "every registered type has a sample that saves, publishes and draws its words, at the top level and in a column, from the copy" do
    with_every_type do
      assert_includes sampled_types.map(&:name), "gallery/album", "the outside type is in the run"
      page = create_page(title: "Samples")
      sample_every_type(page)
      publish_changes(page)

      get path_of(page)
      assert_response :success
      assert_shows_drawn(response.body, "once published")

      # Around the services and without publishing, as the canary does at
      # full depth: every setting, every translated setting, and each column
      # the type uses.
      page.content_blocks.find_each do |block|
        uses = block.definition&.uses_columns.to_a
        columns = { settings: block.settings.to_h.transform_values { CANARY },
                    translated_settings: block.translated_settings.to_h.transform_values { |values| values.to_h.transform_values { CANARY } } }
        (uses & %w[caption alt]).each { |column| columns[column.to_sym] = { "en" => CANARY } }
        columns[:body] = { "en" => rich_doc(CANARY) } if uses.include?("body")
        block.update_columns(columns) # version: none (a test overwrites rows around the services)
      end
      get path_of(page)
      assert_response :success
      assert_not_includes response.body, CANARY, "the page is drawn from the copy, not from the rows"
      assert_shows_drawn(response.body, "from the copy after the rows were overwritten")

      assert_every_type_built
    end
  end

  # Review focus 3: a sample that leaves a column its type uses, or a field
  # of its schema, empty would let every shared test pass while that value is
  # never compared with the rows.
  test "a sample fills every column its type uses and every field of its schema, and names at least one text the public page shows" do
    with_every_type do
      sampled_types.each do |definition|
        sample = definition.sample
        english = sample.translations.fetch("en", {}).transform_keys(&:to_s)
        definition.uses_columns.each do |column|
          filled =
            case column
            when "body" then sample.body.present?
            when "image" then sample.image
            else english[column].present?
            end
          assert filled, "#{definition.name}'s sample leaves #{column} empty, so no shared test compares it"
        end

        excused = UNFILLED_FIELDS.fetch(definition.name, {})
        definition.fields.reject(&:group?).each do |field|
          filled = sample.settings.key?(field.name) || english[field.name].present?
          if excused.key?(field.name)
            assert_not filled, "#{definition.name}'s sample fills #{field.name} now: take it out of UNFILLED_FIELDS"
          else
            assert filled, "#{definition.name}'s sample leaves the field #{field.name} empty, so the canary never compares it: fill it, or name it in UNFILLED_FIELDS with the test that compares it"
          end
        end
        unknown = excused.keys - definition.fields.map(&:name)
        assert_empty unknown, "UNFILLED_FIELDS names #{unknown.join(", ")}, which #{definition.name} has no field of"
        assert_not_empty sample.shows
      end
    end
  end
end
