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
    post_record.update!(body: rich_doc("English"))

    patch "/cs-studio/posts/#{post_record.id}",
      params: { locale: "de", post: { body: rich_doc("Deutsch").to_json }, base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    stored = post_record.reload.read_attribute(:body)
    assert_equal rich_doc("Deutsch"), stored["de"]
    assert_equal rich_doc("English"), stored["en"]
  end

  test "an invalid body document answers 422 and leaves the stored document alone" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body: rich_doc("Kept"))
    invalid = { "type" => "doc", "content" => [ { "type" => "youtube", "attrs" => { "id" => "nope" } } ] }

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { body: invalid.to_json }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, "Couldn"
    assert_select_in_stream "post-body-errors", /youtube/
    assert_equal rich_doc("Kept"), post_record.reload.body_document(locale: "en").to_h
  end

  # The interim Markdown textarea is gone (Task 7): the Tiptap editor writes
  # the document JSON into `post[body]` and that is the only body param. A
  # stray `body_markdown` (an old tab, a hand-built request) is ignored
  # outright rather than converted.
  test "a body_markdown param is ignored" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body: rich_doc("Kept"))

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { title: "Renamed", body_markdown: "Replaced **text**" }, base_updated_at: post_record.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    assert_equal "Renamed", post_record.reload.title(locale: :en)
    assert_equal rich_doc("Kept"), post_record.body_document(locale: "en").to_h
  end

  test "the editor mounts the Tiptap editor on the hidden JSON input" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body: rich_doc("Hello **there**"))

    get "/cs-studio/posts/#{post_record.id}"

    assert_response :success
    assert_select "textarea[name='post[body_markdown]']", count: 0
    assert_select "[data-controller='admin--rich-text'] input[type=hidden][name='post[body]']" do |inputs|
      assert_equal rich_doc("Hello **there**"), JSON.parse(inputs.first["value"])
    end
    assert_select "[data-controller='admin--rich-text'][data-admin--rich-text-locale-value='en']"
  end

  test "a translation shows the primary language's body rendered read-only" do
    post_record = create_post(title: "Engineer")
    post_record.update!(body: rich_doc("Hello **there**"))

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

  # Related posts (design spec §6.1). The picker's hidden-field contract:
  # the section always submits a blank sentinel `post[related_post_ids][]`
  # plus one entry per related post, so the key is present exactly when the
  # picker was rendered -- an autosave PATCH from a form without it (or any
  # other client) leaves the relations alone rather than clearing them.
  test "the editor renders the related-posts picker with the current relations" do
    post_record = create_post(title: "A")
    related = create_post(title: "Related one")
    linking = create_post(title: "Links here")
    PostRelation.create!(post: post_record, related_post: related)
    PostRelation.create!(post: linking, related_post: post_record)

    get "/cs-studio/posts/#{post_record.id}"

    assert_select "[data-controller~='admin--related-posts'][data-admin--related-posts-search-url-value='/cs-studio/link_targets?type=post']" do
      assert_select "input[type=hidden][name='post[related_post_ids][]'][value='']", 1
      assert_select "input[type=hidden][name='post[related_post_ids][]'][value='#{related.id}']", 1
      assert_select "li", text: /Related one/
      assert_select "*", text: /Links here/
    end
    assert_select "#post-related_post_ids-errors"
  end

  test "autosaving the related posts replaces them" do
    post_record = create_post(title: "A")
    old = create_post(title: "Old")
    new_one = create_post(title: "New")
    PostRelation.create!(post: post_record, related_post: old)

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { title: "A", related_post_ids: [ "", new_one.id.to_s, post_record.id.to_s ] } }, as: :turbo_stream

    assert_response :success
    assert_equal [ new_one.id ], post_record.post_relations.reload.pluck(:related_post_id)
  end

  test "the sentinel alone clears the related posts" do
    post_record = create_post(title: "A")
    PostRelation.create!(post: post_record, related_post: create_post(title: "Old"))

    patch "/cs-studio/posts/#{post_record.id}", params: { post: { related_post_ids: [ "" ] } }, as: :turbo_stream

    assert_response :success
    assert_empty post_record.post_relations.reload
  end

  test "a PATCH without the key leaves the related posts alone" do
    post_record = create_post(title: "A")
    old = create_post(title: "Old")
    PostRelation.create!(post: post_record, related_post: old)

    patch "/cs-studio/posts/#{post_record.id}", params: { post: { title: "A2" } }, as: :turbo_stream

    assert_response :success
    assert_equal [ old.id ], post_record.post_relations.reload.pluck(:related_post_id)
  end

  test "an unknown related post id answers with the error in its slot" do
    post_record = create_post(title: "A")

    patch "/cs-studio/posts/#{post_record.id}", params: { post: { related_post_ids: [ "", "0" ] } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "post-related_post_ids-errors", /don.t exist/
  end

  # Review Focus 4: a read-only user's forged autosave PATCH -- the editor
  # never sends one for them (Task 7), but the service refuses it anyway,
  # changes nothing, and however often it's repeated logs one coalesced
  # `access.denied`.
  test "a forged PATCH by a read-only user is refused and audited once" do
    post_record = create_post(title: "Hands off")
    sign_out
    sign_in_as(users(:reader))

    2.times do |attempt|
      patch "/cs-studio/posts/#{post_record.id}", params: { post: { title: "Forged #{attempt}" } }, as: :turbo_stream
      assert_response :forbidden # a permission refusal, not a validation failure (Task 7)
    end

    assert_equal "Hands off", post_record.reload.title
    denied = Audit::Event.where(action: "access.denied")
    assert_equal 1, denied.count
    assert_equal users(:reader), denied.first.actor
    assert_equal post_record, denied.first.subject
    assert_equal "posts.edit", denied.first.metadata["permission"]
    assert_not Audit::Event.exists?(action: "post.updated", subject: post_record)
  end

  # Task 10: deleting moves the post to the trash (`Trash::Move`) with a
  # flash naming it and an Undo that posts straight back to
  # `Admin::TrashController#restore` with `from=undo` -- landing the actor
  # back on this post's own editor rather than the Trash list, the same
  # shape `Admin::PageEditorTest`'s own Undo test gives a page.
  test "deleting a post moves it to the trash and offers Undo" do
    post_record = create_post(title: "Gone post")

    delete "/cs-studio/posts/#{post_record.id}"
    assert_response :see_other
    assert post_record.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_match "Moved “Gone post” to the trash", response.body
    undo_url = admin_restore_trash_item_path("post", post_record, from: "undo")
    assert_select "form[action='#{undo_url}'] button", text: "Undo"

    post undo_url
    assert_response :see_other
    assert_not post_record.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_match "Restored “Gone post”", response.body
  end
end
