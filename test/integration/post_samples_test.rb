require "test_helper"

# THE DERIVED SMOKE TEST OF THE POST TYPES (post types spec, §10): every
# declared content type's sample saves, publishes and is drawn on its post's
# own page and in its list. A type joins this by declaring its sample; nobody
# writes a row for it. `test/event` (test/support/test_types.rb) is declared
# too, so a type with an owner's name runs as well.
class PostSamplesTest < ActionDispatch::IntegrationTest
  include TestTypes

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  def main_of(path)
    get path
    assert_response :success, path
    Nokogiri::HTML5(response.body).at_css("main").to_html
  end

  test "every declared post type's sample is drawn on its detail page and in its list: each shows text on one of the two, and each page draws one of the sample's own values" do
    with_test_types do
      assert_includes ContentTypes.names, "test/event"

      ContentTypes.all.each do |type|
        posts_of_type = sample_post(type.name)
        listing = create_page(title: "List of #{type.label}")
        assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => type.name } }).ok?
        publish_changes(listing)
        publish_changes(posts_of_type)

        detail = main_of(PublicSite::Urls.new.path_for(posts_of_type.reload, "en"))
        list = main_of(PublicSite::Urls.new.path_for(listing.reload, "en"))

        sample = type.sample
        own = [ sample.title, sample.excerpt, sample.body, *sample.fields.values.grep(String) ].compact_blank
        assert own.any? { |value| detail.include?(value) }, "#{type.name}'s detail page draws none of its sample's own values"
        assert own.any? { |value| list.include?(value) }, "#{type.name}'s list draws none of its sample's own values"
        type.sample.shows.each do |text|
          assert_includes detail + list, text, "#{type.name}'s sample shows #{text.inspect}, on neither its detail page nor its list"
        end
      end
    end
  end
end
