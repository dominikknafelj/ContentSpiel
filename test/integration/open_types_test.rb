require "test_helper"

# The open-type proof (open-types spec §1 success, §8): a block type, a
# content type and the field group it embeds, registered nowhere but
# `test/support/test_types.rb`, need no migration and no enum edit, yet
# render through their components, get canonical URLs, validate typed
# (including translated and nested-group) values through the write-path
# services, and show up in the MCP schema -- everywhere a built-in type does.
class OpenTypesTest < ActionDispatch::IntegrationTest
  include TestTypes

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "a new block type needs no migration and renders through its component" do
    with_test_types do
      page = create_page(title: "Quotes")
      result = ContentBlocks::Save.call(page.content_blocks.build, attributes: { block_type: "test/quote", settings: { cite: "https://example.org" } },
        translations: { "en" => { settings: { text: "Hello" } } })
      assert result.ok?, result.errors.to_sentence

      get "/quotes"

      assert_response :success
      assert_select "blockquote", /Hello/
    end
  end

  test "a new content type gets canonical URLs, MCP schema entries and typed validation" do
    with_test_types do
      listing = create_page(title: "Events")
      block_result = ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "test/event" } })
      assert block_result.ok?, block_result.errors.to_sentence

      ok = Posts::Save.call(attributes: { content_type: "test/event", published: true, fields: { venue: "Hall", speakers: [ { name: "Ada" } ] } },
        translations: { "en" => { title: "Launch" } })
      assert ok.ok?, ok.errors.to_sentence
      assert_equal "/events/launch", ok.record.full_path("en")

      bad = Posts::Save.call(attributes: { content_type: "test/event", fields: { speakers: [ { name: "" } ] } }, translations: { "en" => { title: "Bad" } })
      assert_not bad.ok?

      # The per-field path survives all the way to the record's own errors,
      # just humanized: `ContentModel::FieldSet#validate_group` keys the
      # error "speakers.0.name" (spec §3.4), `Post#fields_are_valid` prefixes
      # it "fields.speakers.0.name", and `ActiveModel::Error.full_message`
      # renders a dotted attribute by turning every "." into "_" before
      # humanizing (see `active_model/error.rb`), which is why the dots
      # become spaces here rather than surviving into the message verbatim.
      assert bad.errors.any? { |message| message.match?(/speakers.*0.*name/i) },
        "expected a per-field error naming speakers.0.name, got #{bad.errors.inspect}"

      schema = Mcp::Tools::CreatePost.input_schema.to_h
      assert_includes schema.dig(:properties, :content_type, :enum), "test/event"
    end
  end
end
