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

  test "a post: scheduling in the past is refused with the dialog's own message, a future time schedules, Remove schedule goes back to draft" do
    post_record = create_post(title: "Later", published: false)
    travel_to Time.zone.local(2026, 10, 4, 12, 0) do
      post schedule_admin_post_path(post_record), params: { published_at: "2026-10-04T12:00" }
      follow_redirect!
      assert_select "dialog#schedule-post-#{post_record.id}[data-admin--dialog-open-on-load] [role=alert]", text: "Pick a time in the future."
      assert_select "#toasts .admin-toast", count: 0
      assert_nil post_record.reload.published_at

      post schedule_admin_post_path(post_record), params: { published_at: "" }
      follow_redirect!
      assert_select "dialog#schedule-post-#{post_record.id} [role=alert]", text: "Choose a date and time"

      post schedule_admin_post_path(post_record), params: { published_at: "2026-10-06T09:00" }
      assert_equal "scheduled", post_record.reload.status
      get admin_post_path(post_record)
      assert_select "dialog#schedule-post-#{post_record.id} form input[name=remove][value='1'] ~ button", text: "Remove schedule"

      post schedule_admin_post_path(post_record), params: { remove: "1" }
      assert_nil post_record.reload.published_at
    end
  end

  test "a post's Schedule dialog names the site time zone" do
    site_settings(:default).update!(time_zone: "Berlin")
    post_record = create_post(title: "Later", published: false)
    get admin_post_path(post_record)
    assert_select "dialog#schedule-post-#{post_record.id}", text: /Berlin time \(GMT\+[12]\), the site’s time zone\./
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

  test "a save made on a stale base is refused, names who changed it, and keeps the newer text" do
    post_record = create_post(title: "Engineer")
    stale = post_record.updated_at.iso8601(6)
    travel 2.seconds
    as(users(:two), channel: :admin) { Posts::Save.call(post_record, translations: { "en" => { excerpt: "Changed by someone else" } }) }

    patch "/cs-studio/posts/#{post_record.id}", params: { base_updated_at: stale, post: { excerpt: "My stale edit" } }, as: :turbo_stream
    assert_response :conflict
    assert_equal "Changed by someone else", post_record.reload.excerpt
    assert_select_in_stream "post-save-status", /CHANGED ELSEWHERE/
    assert_select_in_stream "editor-notice", /Changed by .+Reload/m
    assert_no_match(/post-base-updated-at/, response.body)
  end

  test "another editor's tag-only change makes a stale form's save a 409, and the tags stay theirs" do
    post_record = create_post(title: "Engineer", tags: [ "ruby" ])
    stale = post_record.updated_at.iso8601(6)
    travel 2.seconds
    as(users(:two), channel: :admin) { Posts::Save.call(post_record, attributes: { tag_names: [ "ruby", "rails" ] }) }

    patch "/cs-studio/posts/#{post_record.id}", params: { base_updated_at: stale, post: { tag_names: "ruby" } }, as: :turbo_stream
    assert_response :conflict
    assert_equal %w[rails ruby], post_record.reload.tags.map(&:name).sort
  end

  test "a view-only post editor says so" do
    post_record = create_post(title: "Engineer", published: false)
    sign_in_as(users(:reader))
    get "/cs-studio/posts/#{post_record.id}"
    assert_select "[data-view-only-hint]", "You can view this post but not change it."
    assert_select ".admin-view-only"
  end

  test "a post save on a current base still saves" do
    post_record = create_post(title: "Engineer")
    patch "/cs-studio/posts/#{post_record.id}", params: { base_updated_at: post_record.updated_at.iso8601(6), post: { excerpt: "Fresh" } }, as: :turbo_stream
    assert_response :success
    assert_equal "Fresh", post_record.reload.excerpt
  end

  test "the editor has an empty notice slot a stream can target" do
    get "/cs-studio/posts/#{create_post(title: "Engineer").id}"
    assert_select "#editor-notice:empty"
  end

  # Design pass round 2 (handoff §9 B23): the type's own fields are one group
  # between Excerpt and Body, titled with the type's label.
  test "the content type's fields sit in their own titled group between Excerpt and Body" do
    post_record = create_post(title: "Engineer", content_type: "resume_entry")
    get "/cs-studio/posts/#{post_record.id}"
    assert_response :success
    assert_select "[data-editor-fields-group] [data-fields-group-title]", text: "Resume entry fields"
    assert_select "[data-editor-fields-group] input[name='post[fields][start_date]'][type=text][pattern][placeholder='yyyy-mm-dd']"
    assert_select "[data-editor-fields-group] select.cs-select[name='post[fields][role_type]']"
    body = response.body
    assert body.index('data-field-name="excerpt"') < body.index("data-editor-fields-group")
    assert body.index("data-editor-fields-group") < body.index('data-field-name="body"')
  end

  test "a date typed in the wrong form is a field error after the save, not a 500" do
    post_record = create_post(title: "Engineer", content_type: "resume_entry")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { fields: { start_date: "2024-13-45" } }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select_in_stream "post-start_date-errors", /\A\s*!?\s*Start date must use the form yyyy-mm-dd\s*\z/
    assert_nil post_record.reload.fields.start_date
  end

  test "a row error in the CS Studio slot reads as group, row and sub-field" do
    with_test_types do
      post_record = create_post(title: "Launch", content_type: "test/event")
      patch "/cs-studio/posts/#{post_record.id}",
        params: { post: { fields: { speakers: [ { name: "" } ] } }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_select_in_stream "post_fields_speakers_0-name-errors", /\A\s*!?\s*Speakers, row 1: name can't be blank\s*\z/
    end
  end

  test "a required scalar's error in the slot reads as its label and message" do
    with_test_types do
      ContentTypes.register "test/required_company" do |t|
        t.label "Required company"
        t.color "#f59e0b"
        t.list_component Posts::BlogListComponent
        t.detail_component Posts::DetailComponent
        t.field :company, :string, required: true
      end
      post_record = Post.create!(content_type: "test/required_company", title: "Role", metadata: { "company" => "Acme" })
      patch "/cs-studio/posts/#{post_record.id}",
        params: { post: { fields: { company: "" } }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_select_in_stream "post-company-errors", /\A\s*!?\s*Company can't be blank\s*\z/
    end
  end

  test "only a strict yyyy-mm-dd date is accepted" do
    post_record = create_post(title: "Engineer", content_type: "resume_entry")
    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { fields: { start_date: "20240101" } }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { fields: { start_date: "2024-01-31" } }, base_updated_at: post_record.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal Date.new(2024, 1, 31), post_record.reload.fields.start_date
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

  test "Move to trash answers the whole page, so the sidebar's Trash badge updates" do
    post_record = create_post(title: "Engineer")
    get "/cs-studio/posts/#{post_record.id}"
    assert_select "dialog form[action^='/cs-studio/posts/#{post_record.id}'][data-turbo-frame='_top'] input[name='_method'][value='delete']"
  end

  # The error toast never auto-hides, so it must not pile up or outlive the
  # error: each form owns one toast with a stable id (`toast-<error prefix>`).
  # A failed autosave takes the previous one away before appending its own,
  # and the next successful save removes it.
  test "a failed autosave streams one error toast with a stable id, and the next good save removes it" do
    post_record = create_post(title: "Engineer")
    invalid = { "type" => "doc", "content" => [ { "type" => "youtube", "attrs" => { "id" => "nope" } } ] }

    2.times do
      patch "/cs-studio/posts/#{post_record.id}",
        params: { post: { body: invalid.to_json }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_select "turbo-stream[action='remove'][target='toast-post']", count: 1
      assert_select "turbo-stream[action='append'][target='toasts']", count: 1
      assert_select "turbo-stream[action='append'][target='toasts'] .admin-toast#toast-post[role=alert]", count: 1, text: /Couldn.t save your changes\./
      assert_operator response.body.index("action=\"remove\" target=\"toast-post\""), :<, response.body.index("target=\"toasts\""),
        "the old toast goes before the new one arrives"
    end

    patch "/cs-studio/posts/#{post_record.id}",
      params: { post: { title: "Engineer II" }, base_updated_at: post_record.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='remove'][target='toast-post']", count: 1
    assert_select "turbo-stream[target='toasts']", count: 0
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

  # Translation helpers spec §4 (Task 4): the "Languages" column shows one
  # chip per *target* language -- plain complete, ○ missing, ↻ outdated --
  # each with a title and an accessible label, and none for the original.
  # (Chip labels: Task 5 of the design pass; no red, no ✓/! glyphs.)
  test "the list shows a translation badge per target language" do
    with_locales(%w[en de es], default: "en")
    post_record = create_post(title: "Hello")
    assert Posts::Save.call(post_record, translations: { "de" => { title: "Hallo" } }).ok?
    stale = create_post(title: "Stale")
    assert Posts::Save.call(stale, translations: { "de" => { title: "Alt" }, "es" => { title: "Viejo" } }).ok?
    assert Posts::Save.call(stale, translations: { "en" => { title: "Stale!" } }).ok?

    get "/cs-studio/posts"

    assert_response :success
    assert_select "tr#post_#{post_record.id}" do
      assert_select "[data-translation-state][data-locale='en']", count: 0
      assert_select "[data-locale='de'][data-translation-state='complete'][title='Translated'][aria-label='Deutsch: translated']", text: "de"
      assert_select "[data-locale='es'][data-translation-state='missing'][title='Not translated'][aria-label='Español: not translated']", text: /○/
    end
    assert_select "tr#post_#{stale.id}" do
      assert_select "[data-locale='de'][data-translation-state='outdated'][aria-label='Deutsch: outdated'][title='English changed since translation']", text: /↻/
      assert_select "[data-locale='es'][data-translation-state='outdated']"
    end
  end

  test "the list costs the same queries for 1 post as for 20" do
    with_locales(%w[en de es], default: "en")
    create_post(title: "First", tags: [ "first" ])
    get "/cs-studio/posts"
    one = count_queries { get "/cs-studio/posts" }

    19.times { |index| create_post(title: "Post #{index}", tags: [ "tag#{index}" ]) }
    twenty = count_queries { get "/cs-studio/posts" }

    assert_response :success
    assert_select "tbody tr", 20
    assert_equal one, twenty
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

  # -- side-by-side translation (design pass round 2, Task 7) --

  def with_mixed_type
    with_test_types do
      ContentTypes.register "test/mixed" do |t|
        t.label "Mixed"
        t.color "#f59e0b"
        t.list_component Posts::BlogListComponent
        t.detail_component Posts::DetailComponent
        t.field :blurb, :string, translated: true
        t.field :venue, :string
        t.field :capacity, :integer
      end
      yield
    end
  end

  test "on a translation tab a translated field is a pair and the untranslated ones live only in Shared fields" do
    with_mixed_type do
      post_record = Posts::Save.call(Post.new, attributes: { content_type: "test/mixed", fields: { venue: "Main Hall", capacity: 120 } },
        translations: { Locales.default => { title: "Launch", fields: { blurb: "Hello" } } }).record
      assert post_record.persisted?

      get admin_post_path(post_record, locale: "de")

      assert_select "form.admin-translation-form"
      assert_select "[data-field-name='blurb'] .admin-translation-pair [data-original-for='blurb']"
      assert_select "[data-field-name='title'] .admin-translation-pair [data-original-for='title']"
      assert_select "details.admin-shared-fields > summary", text: "Shared fields (2)"
      assert_select "details.admin-shared-fields:not([open])"
      assert_select "details.admin-shared-fields", text: /Main Hall/
      assert_select "details.admin-shared-fields", text: /120/
      assert_select "[data-field-name='venue'], [data-field-name='capacity']", count: 0
      assert_select "form input[name='post[fields][venue]'], form input[name='post[fields][capacity]']", count: 0
      assert_select "form input[name='post[fields][blurb]']", count: 1
    end
  end

  test "on the default tab every field of the type is an ordinary input and there are no shared fields" do
    with_mixed_type do
      post_record = Posts::Save.call(Post.new, attributes: { content_type: "test/mixed", fields: { venue: "Main Hall", capacity: 120 } },
        translations: { Locales.default => { title: "Launch", fields: { blurb: "Hello" } } }).record

      get admin_post_path(post_record, locale: Locales.default)

      assert_select "input[name='post[fields][blurb]']"
      assert_select "input[name='post[fields][venue]']"
      assert_select "input[name='post[fields][capacity]']"
      assert_select ".admin-translation-pair", count: 0
      assert_select "details.admin-shared-fields", count: 0
    end
  end

  test "saving a translation tab leaves the shared values untouched" do
    with_mixed_type do
      post_record = Posts::Save.call(Post.new, attributes: { content_type: "test/mixed", fields: { venue: "Main Hall", capacity: 120 } },
        translations: { Locales.default => { title: "Launch", fields: { blurb: "Hello" } } }).record

      patch admin_post_path(post_record), params: {
        locale: "de", base_updated_at: post_record.updated_at.iso8601(6),
        post: { title: "Start", fields: { blurb: "Hallo" } }
      }, as: :turbo_stream

      assert_response :success
      post_record.reload
      assert_equal "Start", post_record.title(locale: :de)
      assert_equal "Hallo", post_record.fields(locale: :de).blurb
      assert_equal "Main Hall", post_record.fields(locale: Locales.default).venue
      assert_equal 120, post_record.fields(locale: Locales.default).capacity
    end
  end

  private

  # Every SQL statement the block issues, cached or not (see
  # `Admin::AccessControlTest#count_queries`).
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
