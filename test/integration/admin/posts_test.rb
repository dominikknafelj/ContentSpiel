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
  # RichTextColumnComponent` fix (`name` -> `html_name`) -- before it, this
  # form's Trix editor submitted a top-level `body` param instead of
  # `post[body]`, so `post_params.permit(*TRANSLATED_COLUMNS)` never saw it
  # and the save silently no-opped on the body itself.
  test "the body autosaves" do
    post_record = create_post(title: "Engineer")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: "<p>Hello there</p>" }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_includes post_record.reload.body(locale: :en).to_s, "Hello there"
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
end
