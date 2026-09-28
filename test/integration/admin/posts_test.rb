require "test_helper"

class Admin::PostsTest < ActionDispatch::IntegrationTest
  # `with_test_types` (last test below) is only defined once this module is
  # mixed in -- every other test file that calls it does the same (see
  # `test/support/test_types.rb`'s own comment); the brief's own snippet
  # omits this line, but it's load-bearing, not optional.
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list filters by type, status and tag" do
    create_post(title: "Blog one", tags: [ "rails" ])
    create_post(title: "Resume one", content_type: "resume_entry")
    create_post(title: "Draft one", published: false)
    get "/cs-studio/posts", params: { type: "blog", status: "live", tag: "rails" }
    assert_select "tbody tr", 1
    assert_select "tbody tr", /Blog one/
  end

  # Fix (final-fixes round, finding 6): filtering by tag used to combine
  # `joins(:tags).where(tags: { name: ... })` with `index`'s own
  # `.includes(:tags)`, which Rails silently upgrades into a single
  # `eager_load` once both reference the same table -- so a post matching
  # the filter by having *one* of several tags showed only that one tag in
  # the list, not every tag it actually has.
  test "filtering by tag still shows every tag on a matching row, not just the one it matched by" do
    create_post(title: "Multi-tagged", tags: [ "rails", "ruby" ])
    get "/cs-studio/posts", params: { tag: "rails" }
    assert_select "tbody tr", 1
    assert_select "tbody tr", /rails, ruby/
  end

  test "new asks for the type, then opens the editor" do
    post "/cs-studio/posts", params: { post: { content_type: "resume_entry", title: "Engineer" } }
    created = Post.order(:id).last
    assert_redirected_to "/cs-studio/posts/#{created.id}"
    assert_equal "draft", created.status
  end

  test "typed fields and tags autosave" do
    post_record = create_post(title: "Engineer", content_type: "resume_entry")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { fields: { company: "Acme", role_type: "lead" }, tag_names: "ruby, rails" }, base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_equal "Acme", post_record.reload.fields.company
    assert_equal %w[rails ruby], post_record.tags.map(&:name).sort
  end

  # Fix round 1 (Task 7 review): regression test for the `Admin::Columns::
  # RichTextColumnComponent` fix (`name` -> `html_name`) -- the body has to
  # arrive nested as `post[body]` or `post_params.permit(*TRANSLATED_COLUMNS)`
  # never sees it. Since the JSON-document switch the `body` param is the
  # hidden input's document JSON String (design spec §4.1).
  test "the body autosaves" do
    post_record = create_post(title: "Engineer")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: rich_doc("Hello there").to_json }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal rich_doc("Hello there"), post_record.reload.body_document(locale: "en").to_h
  end

  test "the body param saves into the locale of the form" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body_doc: rich_doc("English"))

    patch "/cs-studio/posts/#{post_record.id}",
      params: { locale: "de", post: { body: rich_doc("Deutsch").to_json }, base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    stored = post_record.reload.read_attribute(:body_doc)
    assert_equal rich_doc("Deutsch"), stored["de"]
    assert_equal rich_doc("English"), stored["en"]
  end

  test "an invalid body document answers 422 and leaves the stored document alone" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body_doc: rich_doc("Kept"))
    invalid = { "type" => "doc", "content" => [ { "type" => "youtube", "attrs" => { "id" => "nope" } } ] }

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: invalid.to_json }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, "Couldn"
    assert_select_in_stream "post-body-errors", /youtube/
    assert_equal rich_doc("Kept"), post_record.reload.body_document(locale: "en").to_h
  end

  # The interim Markdown textarea (Task 5 -> Task 7): `body_markdown` wins
  # over the hidden JSON `body`, and its conversion warnings land in the
  # field's own warnings slot.
  test "body_markdown is converted server-side and wins over the JSON body" do
    post_record = create_post(title: "Engineer")

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: rich_doc("Stale").to_json, body_markdown: "Fresh **text**\n\n::nope{x=\"1\"}" },
                base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    document = post_record.reload.body_document(locale: "en")
    assert_includes document.to_markdown, "Fresh **text**"
    assert_not_includes document.to_markdown, "Stale"
    assert_select_in_stream "post-body-warnings", /nope/
  end

  # An autosave triggered by some *other* field resends the textarea
  # unchanged; that must not round-trip the stored document through Markdown
  # (lossy for e.g. empty spacer paragraphs), so unchanged Markdown keeps the
  # JSON body instead.
  test "unchanged body_markdown does not rewrite the stored document" do
    post_record = create_post(title: "Engineer")
    spaced = { "type" => "doc", "content" => [
      { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "One" } ] },
      { "type" => "paragraph" },
      { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Two" } ] } ] }
    post_record.update!(body_doc: spaced)
    markdown = post_record.body_document(locale: "en").to_markdown.gsub("\n", "\r\n")

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { title: "Renamed", body: spaced.to_json, body_markdown: markdown }, base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    assert_equal spaced, post_record.reload.body_document(locale: "en").to_h
  end

  # The hidden JSON input is never refreshed by an autosave response, so
  # once the textarea has been edited it holds a stale document; a later
  # save that resends the (now unchanged) Markdown must not let that stale
  # JSON revert the edit.
  test "a stale JSON body never reverts an earlier Markdown edit" do
    post_record = create_post(title: "Engineer")
    stale = RichText::Document.empty.to_h.to_json

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: stale, body_markdown: "Typed" }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { title: "Renamed", body: stale, body_markdown: "Typed" }, base_updated_at: post_record.reload.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    assert_equal rich_doc("Typed"), post_record.reload.body_document(locale: "en").to_h
  end

  test "the editor shows the body as Markdown with the hidden JSON input" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body_doc: rich_doc("Hello **there**"))

    get "/cs-studio/posts/#{post_record.id}"

    assert_response :success
    assert_select "textarea[name='post[body_markdown]']", text: /Hello \*\*there\*\*/
    assert_select "input[type=hidden][name='post[body]']" do |inputs|
      assert_equal rich_doc("Hello **there**"), JSON.parse(inputs.first["value"])
    end
  end

  test "a translation shows the primary language's body rendered read-only" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body_doc: rich_doc("Hello **there**"))

    get "/cs-studio/posts/#{post_record.id}", params: { locale: "de" }

    assert_response :success
    assert_select "[data-original-for=body] strong", text: "there"
  end

  # Fix round 1 (minor): a stray double/trailing comma while typing a
  # comma-separated tag list must not create a blank-named `Tag`.
  test "blank segments in the tag input are dropped" do
    post_record = create_post(title: "Engineer")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { tag_names: "a, , b" }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal %w[a b], post_record.reload.tags.map(&:name).sort
  end

  test "the editor says when a post is not listed anywhere" do
    post_record = create_post(title: "Orphan", content_type: "now_update")
    get "/cs-studio/posts/#{post_record.id}"
    assert_includes response.body, "Not listed on any page yet"
  end

  test "repeatable groups save through the editor" do
    with_test_types do
      post_record = Posts::Save.call(attributes: { content_type: "test/event" }, translations: { "en" => { title: "Launch" } }).record
      patch "/cs-studio/posts/#{post_record.id}",
        params: { post: { fields: { speakers: { "0" => { name: "Ada" }, "1" => { name: "Grace" } } } }, base_updated_at: post_record.updated_at.iso8601(6) },
        as: :turbo_stream
      assert_response :success
      assert_equal %w[Ada Grace], post_record.reload.fields.group(:speakers).map(&:name)
    end
  end

  # Fix (final-fixes round, finding 2): removing every row leaves the
  # browser with no `speakers` key to submit at all -- `Admin::Fields::
  # GroupsField`'s own hidden `groups_present` marker is what's supposed to
  # tell the controller "this field was on the form, just with nothing left
  # in it" apart from "this form never touched this field." Without it, the
  # PATCH below would leave the two speakers saved just above untouched.
  test "removing every speaker saves it as empty, not left unchanged" do
    with_test_types do
      post_record = Posts::Save.call(attributes: { content_type: "test/event" }, translations: { "en" => { title: "Launch" } }).record
      Posts::Save.call(post_record, attributes: { fields: { speakers: [ { name: "Ada" } ] } })
      assert_equal %w[Ada], post_record.reload.fields.group(:speakers).map(&:name)

      patch "/cs-studio/posts/#{post_record.id}",
        params: { post: { groups_present: [ "speakers" ] }, base_updated_at: post_record.updated_at.iso8601(6) },
        as: :turbo_stream
      assert_response :success
      assert_equal [], post_record.reload.fields.group(:speakers).map(&:name)
    end
  end
end
