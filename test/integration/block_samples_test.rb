require "test_helper"

# THE DERIVED PUBLIC SMOKE TEST (block types spec, "New guards"): every
# registered block type's sample saves, publishes and draws its words, at the
# top level and in a column, and the page draws them from the published copy.
# A type joins this by declaring its sample; nobody writes a row for it.
# `test/quote` (test/support/test_types.rb) is registered too, so the test
# also runs a type with an owner's name.
class BlockSamplesTest < ActionDispatch::IntegrationTest
  include TestTypes

  CANARY = "SAMPLE-CANARY-41d0".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    create_post(title: "A listed post")
  end

  def path_of(page) = PublicSite::Urls.new.path_for(page.reload, "en")

  test "every registered type has a sample that saves, publishes and draws its words, at the top level and in a column, from the copy" do
    with_test_types do
      page = create_page(title: "Samples")
      sample_every_type(page)
      publish_changes(page)

      get path_of(page)
      assert_response :success
      main = Nokogiri::HTML5(response.body).at_css("main").to_html
      sampled_types.each do |definition|
        definition.sample.shows.each { |text| assert_includes main, text, "#{definition.name}'s sample draws #{text.inspect}" }
      end
      column = Nokogiri::HTML5(response.body).css(".content-section__column").first&.to_html.to_s
      sampled_types.reject { |definition| definition.capability?(:container) }.each do |definition|
        next if sampled_types.none? { |each| each.capability?(:container) }

        definition.sample.shows.each { |text| assert_includes column, text, "#{definition.name}'s sample draws #{text.inspect} in a column" }
      end

      # Around the services and without publishing, as the canary does at
      # full depth: every setting, and the caption where the type uses one.
      page.content_blocks.find_each do |block|
        columns = { settings: block.settings.to_h.transform_values { CANARY } }
        columns[:caption] = { "en" => CANARY } if block.definition&.uses_columns&.include?("caption")
        block.update_columns(columns)
      end
      get path_of(page)
      assert_not_includes response.body, CANARY, "the page is drawn from the copy, not from the rows"

      assert_every_type_built
    end
  end

  # Review focus 3: a sample that leaves a column its type uses empty would
  # let every shared test pass while that column is never compared.
  test "a sample fills every column its type uses and names at least one text the public page shows" do
    with_test_types do
      sampled_types.each do |definition|
        sample = definition.sample
        definition.uses_columns.each do |column|
          filled =
            case column
            when "body" then sample.body.present?
            when "image" then sample.image
            else sample.translations.fetch("en", {}).transform_keys(&:to_s)[column].present?
            end
          assert filled, "#{definition.name}'s sample leaves #{column} empty, so no shared test compares it"
        end
        assert_not_empty sample.shows
      end
    end
  end
end
