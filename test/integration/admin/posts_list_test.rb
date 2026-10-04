require "test_helper"

# The posts list (design pass round 2, Task 17): toolbar filters and counts,
# 50 to a page, the Languages column, and the bulk bar's two actions
# (`POST /posts/bulk`, `Posts::Bulk`) with the Undo a bulk trash offers
# (`POST /trash/restore_many`).
class Admin::PostsListTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  # Many posts quickly: the list only reads rows, so they are inserted
  # straight (the services are covered by their own tests). `age` spreads
  # `updated_at` so the order is known: the first inserted is the newest.
  def insert_posts(count, prefix: "Bulk", published_at: nil)
    now = Time.current
    rows = Array.new(count) do |i|
      { title: { "en" => "#{prefix} #{format("%03d", i + 1)}" }, content_type: "blog", published_at: published_at,
        created_at: now - i.minutes, updated_at: now - i.minutes }
    end
    Post.insert_all(rows)
  end

  def row_titles = css_select("tbody tr td:nth-child(2) span:first-child").map { |node| node.text.strip }

  def query_count
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # --- filters, counts, pagination ------------------------------------------

  test "the scope counts ignore the scope itself but respect every other filter" do
    create_post(title: "Live blog", published: true, tags: [ "rails" ])
    create_post(title: "Draft blog", published: false, tags: [ "rails" ])
    create_post(title: "Draft other", published: false)
    scheduled = create_post(title: "Later blog", published: false, tags: [ "rails" ])
    Posts::Save.call(scheduled, attributes: { published_at: 3.days.from_now })
    create_post(title: "Resume", content_type: "resume_entry", published: true)

    get "/cs-studio/posts", params: { scope: "drafts" }
    assert_select "label[for=posts-scope-all] span.font-cs-mono", text: "5"
    assert_select "label[for=posts-scope-live] span.font-cs-mono", text: "2"
    assert_select "label[for=posts-scope-drafts] span.font-cs-mono", text: "2"
    assert_select "label[for=posts-scope-scheduled] span.font-cs-mono", text: "1"
    assert_select "input#posts-scope-drafts[checked]"
    assert_equal [ "Draft other", "Draft blog" ].sort, row_titles.sort

    get "/cs-studio/posts", params: { scope: "live", tag: "rails" }
    assert_equal [ "Live blog" ], row_titles
    assert_select "label[for=posts-scope-all] span.font-cs-mono", text: "3"
    assert_select "label[for=posts-scope-drafts] span.font-cs-mono", text: "1"

    get "/cs-studio/posts", params: { type: "resume_entry" }
    assert_select "label[for=posts-scope-all] span.font-cs-mono", text: "1"
  end

  test "the old status param still works, and scope wins when both are sent" do
    create_post(title: "Live one", published: true)
    create_post(title: "Draft one", published: false)
    get "/cs-studio/posts", params: { status: "draft" }
    assert_equal [ "Draft one" ], row_titles
    get "/cs-studio/posts", params: { status: "draft", scope: "live" }
    assert_equal [ "Live one" ], row_titles
    get "/cs-studio/posts", params: { scope: "bogus" }
    assert_equal 2, row_titles.size
  end

  test "the search matches titles in the editing language, with bound LIKE input" do
    create_post(title: "100% real")
    create_post(title: "Plain")
    get "/cs-studio/posts", params: { q: "%" }
    assert_equal [ "100% real" ], row_titles
    get "/cs-studio/posts", params: { q: "'; DROP TABLE posts; --" }
    assert_empty row_titles
    assert_equal 2, Post.count
  end

  test "translation=needs, outdated and complete read the stored states of every target language" do
    with_locales(%w[en de], default: "en") do
      complete = create_post(title: "Complete one")
      outdated = create_post(title: "Outdated one")
      missing = create_post(title: "Missing one")
      Translations::State.where(record_type: "Post").delete_all
      { complete => "complete", outdated => "outdated", missing => "missing" }.each do |post, state|
        Translations::State.create!(record_type: "Post", record_id: post.id, locale: "de", state: state,
          missing_count: (state == "missing" ? 1 : 0), outdated_count: (state == "outdated" ? 1 : 0))
      end

      get "/cs-studio/posts", params: { translation: "outdated" }
      assert_equal [ "Outdated one" ], row_titles
      get "/cs-studio/posts", params: { translation: "needs" }
      assert_equal [ "Missing one", "Outdated one" ], row_titles.sort
      get "/cs-studio/posts", params: { translation: "complete" }
      assert_equal [ "Complete one" ], row_titles
      get "/cs-studio/posts", params: { translation: "nonsense" }
      assert_equal 3, row_titles.size
    end
  end

  test "the Languages column links each chip to that language's editor" do
    with_locales(%w[en de], default: "en") do
      post_record = create_post(title: "Chips")
      get "/cs-studio/posts"
      assert_select "tbody tr a[href=?] .admin-translation-chip[data-locale=de]", "/cs-studio/posts/#{post_record.id}?locale=de"
    end
  end

  test "the path under the title is the post's public path, or Not listed" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    create_post(title: "Listed one")
    create_post(title: "Unlisted one", content_type: "resume_entry")
    get "/cs-studio/posts"
    assert_select "tbody tr", text: /Listed one\s*\/blog\/listed-one/
    assert_select "tbody tr", text: /Unlisted one\s*Not listed/
  end

  test "50 to a page: page 2 of 120 lists rows 51-100, and pager links keep the filters" do
    insert_posts(120)
    create_post(title: "Other row", published: false)
    get "/cs-studio/posts", params: { q: "Bulk", page: "2", type: "blog" }
    assert_equal 50, row_titles.size
    assert_equal "Bulk 051", row_titles.first
    assert_equal "Bulk 100", row_titles.last
    assert_select "nav[aria-label=Pagination] p", text: /51–100 OF 120/
    assert_select "nav[aria-label=Pagination] a[href=?]", "/cs-studio/posts?page=3&q=Bulk&type=blog"
    assert_select "nav[aria-label=Pagination] a[href=?]", "/cs-studio/posts?page=1&q=Bulk&type=blog"
  end

  test "junk in page is page 1; a page past the end is reported, not clamped" do
    insert_posts(3)
    get "/cs-studio/posts", params: { page: "abc" }
    assert_equal 3, row_titles.size
    get "/cs-studio/posts", params: { page: "9" }
    assert_response :ok
    assert_select "h3", text: "Nothing on this page"
    assert_select "a[href=?]", "/cs-studio/posts?page=1", text: "Back to page 1"
    assert_select "tbody", count: 0
  end

  test "the list is read-scoped and trash-free, and a trashed post is in no count" do
    kept = create_post(title: "Kept")
    gone = create_post(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    get "/cs-studio/posts"
    assert_equal [ "Kept" ], row_titles
    assert_select "label[for=posts-scope-all] span.font-cs-mono", text: "1"
    assert_not_includes response.body, "Gone"
    assert_includes response.body, "/cs-studio/posts/#{kept.id}"
  end

  test "the list costs the same number of queries for 5 posts as for 40" do
    insert_posts(5, prefix: "Few")
    get "/cs-studio/posts" # warm-up: a session's first request does its own one-off lookups
    few = query_count { get "/cs-studio/posts" }
    assert_equal 5, row_titles.size

    insert_posts(35, prefix: "More")
    many = query_count { get "/cs-studio/posts" }
    assert_equal 40, row_titles.size
    assert_equal few, many

    # And for a viewer whose rights come from a group, not ownership: the
    # per-row "Move to trash" check must not query per row either.
    sign_in_as(users(:two))
    get "/cs-studio/posts" # warm-up: the first request of a session does its own one-off lookups
    few_group = query_count { get "/cs-studio/posts" }
    Post.where("title ->> 'en' LIKE 'More%'").delete_all
    fewer_group = query_count { get "/cs-studio/posts" }
    assert_equal fewer_group, few_group
  end

  test "a viewer who can't publish or delete sees no bulk actions; one who can sees the bar, the trash dialog and the toolbar" do
    create_post(title: "One")
    get "/cs-studio/posts"
    assert_select "[data-admin--bulk-select-target=bar][hidden]"
    assert_select "p[role=status][aria-live=polite][data-admin--bulk-select-target=status]"
    assert_select "[data-admin--bulk-select-target=bar] form[action=?] button", "/cs-studio/posts/bulk", text: "Publish"
    assert_select "dialog#bulk-trash-dialog form[action=?]", "/cs-studio/posts/bulk"
    assert_select "tbody input.cs-checkbox[type=checkbox][data-admin--bulk-select-target=row]", 1
    assert_select "thead input.cs-checkbox[data-admin--bulk-select-target=all][aria-label]"

    sign_in_as(users(:reader))
    get "/cs-studio/posts"
    assert_response :ok
    assert_select "[data-admin--bulk-select-target=bar]", count: 0
    assert_select "dialog#bulk-trash-dialog", count: 0
  end

  test "the New post split button opens the dialog preset to its type; the menu offers the others" do
    get "/cs-studio/posts"
    assert_select "a[data-admin--dialog-id-param=new-post-dialog][data-new-post-type-param=blog]", text: /New blog post/i
    assert_select "[role=menu] a[data-admin--dialog-id-param=new-post-dialog][data-new-post-type-param=resume_entry]", visible: :all
  end

  test "the dashboard's All drafts link opens the list on Drafts" do
    create_post(title: "A draft", published: false)
    create_post(title: "Live one", published: true)
    get "/cs-studio"
    assert_select "a[href=?]", "/cs-studio/posts?scope=drafts"
    get "/cs-studio/posts?scope=drafts"
    assert_equal [ "A draft" ], row_titles
  end

  # --- POST /posts/bulk --------------------------------------------------------

  def toast_text = flash[:notice].presence || flash[:alert]

  test "bulk publish: 'Published 3 posts.' and the filters survive the redirect" do
    posts = Array.new(3) { |i| create_post(title: "Draft #{i}", published: false) }
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: posts.map(&:id), scope: "drafts", q: "Draft", page: "1", evil: "x" }
    # Under Drafts nothing is left, so page 1 of the returned list is simply the list.
    assert_redirected_to "/cs-studio/posts?q=Draft&scope=drafts"
    assert_equal "Published 3 posts.", flash[:notice]
    assert posts.all? { |record| record.reload.live? }
    assert_equal 3, Audit::Event.where(action: "post.published").count
  end

  test "bulk publish reports a refusal by title and keeps going" do
    mine = create_post(title: "Mine", published: false)
    other = create_post(title: "Not mine", published: false)
    mine.update_columns(author_id: users(:reader).id)
    group = AccessControl::Group.create!(name: "Own publishers")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: group, permission: "posts.publish", scope: { "own" => true })
    AccessControl::Membership.create!(group: group, user: users(:reader))
    sign_in_as(users(:reader))

    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ other.id, mine.id ] }
    assert_equal "Published 1 post. 1 was refused: “Not mine”.", flash[:warning]
    assert mine.reload.live?
    assert_nil other.reload.published_at
  end

  test "bulk trash: 'Moved 3 posts to the trash.' with an Undo that restores exactly those, filters kept" do
    older = create_post(title: "Trashed earlier")
    as_owner { Trash::Move.call(older) }
    posts = Array.new(3) { |i| create_post(title: "Move #{i}") }
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: posts.map(&:id), q: "Move", type: "blog" }
    assert_redirected_to "/cs-studio/posts?q=Move&type=blog"
    assert_equal "Moved 3 posts to the trash.", flash[:notice]
    undo = flash[:undo]
    assert_equal "Undo", undo["label"]
    assert posts.all? { |record| record.reload.trashed? }

    follow_redirect!
    assert_select "#toasts .admin-toast form[action^='/cs-studio/trash/restore_many'] button", text: "Undo"

    assert_match %r{\A/cs-studio/trash/restore_many\?}, undo["url"]
    post undo["url"]
    assert_redirected_to "/cs-studio/posts?q=Move&type=blog"
    assert_equal "Restored 3 posts.", flash[:notice]
    assert posts.none? { |record| record.reload.trashed? }
    assert older.reload.trashed?, "a post trashed earlier is not part of the Undo"
  end

  test "bulk with nothing acted on: 'Nothing was changed. 2 posts were not found.' as an error toast" do
    gone = create_post(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ gone.id, 99_999_999 ] }
    assert_equal "Nothing was changed. 2 posts were not found.", flash[:alert]
    assert_nil flash[:notice]
    assert_nil flash[:undo]
  end

  test "a post outside the viewer's scope is not found, never named" do
    hidden = create_post(title: "Secret resume", content_type: "resume_entry", published: false)
    # A fresh user: the fixture reader also sits in the unscoped Read only group.
    scoped = User.create!(email_address: "blog-only@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Blog only")
    %w[posts.read posts.publish posts.delete].each do |key|
      AccessControl::Grant.create!(group: group, permission: key, scope: { "content_types" => [ "blog" ] })
    end
    AccessControl::Membership.create!(group: group, user: scoped)
    sign_in_as(scoped)
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ hidden.id ] }
    assert_equal "Nothing was changed. 1 post was not found.", flash[:alert]
    assert_not_includes flash[:alert], "Secret"
    assert_nil hidden.reload.published_at
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  test "a forged action is a 422; so is too big a selection; no ids is a plain redirect" do
    post "/cs-studio/posts/bulk", params: { bulk_action: "delete", ids: [ 1 ] }
    assert_response :unprocessable_entity
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: (1..201).map(&:to_s) }
    assert_response :unprocessable_entity
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: { "a" => "1" } }
    assert_redirected_to "/cs-studio/posts"
    assert_equal "Select at least one post.", flash[:alert]
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish" }
    assert_equal "Select at least one post.", flash[:alert]
  end

  test "a forged list param can't redirect anywhere else" do
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ "1" ], script_name: "//evil.example", host: "evil.example", q: { "a" => "b" } }
    assert_redirected_to "/cs-studio/posts"
  end

  test "a viewer without posts.read can't use the endpoint at all" do
    group_less = User.create!(email_address: "nogroups@example.com", password: "a long enough password")
    sign_in_as(group_less)
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ "1" ] }
    assert_response :forbidden
  end

  test "an invalid post is 'couldn't be published' with its reason, apart from a denied one; plural-correct" do
    ok = create_post(title: "Ok", published: false)
    bad1 = create_post(title: "Bad one", published: false)
    bad2 = create_post(title: "Bad two", published: false)
    [ bad1, bad2 ].each { |bad| bad.update_columns(content_type: "not_registered") }
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ ok.id, bad1.id ] }
    assert_match(/\APublished 1 post\. 1 couldn't be published: “Bad one” \(.+\)\.\z/, flash[:warning])
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ bad1.id, bad2.id ] }
    assert_match(/\ANothing was changed\. 2 couldn't be published: “Bad one” and “Bad two” \(.+\)\.\z/, flash[:alert])
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: [ bad1.id ] }
    assert_match(/Moved 1 post to the trash\./, flash[:notice]) # a trash doesn't validate; sanity that the phrase is per action
  end

  test "a denied post and an invalid one in one batch are two sentences" do
    mine = create_post(title: "Mine", published: false)
    other = create_post(title: "Not mine", published: false)
    bad = create_post(title: "Broken", published: false)
    bad.update_columns(content_type: "not_registered", author_id: users(:reader).id)
    mine.update_columns(author_id: users(:reader).id)
    group = AccessControl::Group.create!(name: "Own publishers 2")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: group, permission: "posts.publish", scope: { "own" => true })
    AccessControl::Membership.create!(group: group, user: users(:reader))
    sign_in_as(users(:reader))
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ mine.id, other.id, bad.id ] }
    assert_match(/\APublished 1 post\. 1 was refused: “Not mine”\. 1 couldn't be published: “Broken” \(.+\)\.\z/, flash[:warning])
  end

  test "bulk publish skips a scheduled post and says so; an already-live one is not counted as published" do
    live = create_post(title: "Live", published: true)
    draft = create_post(title: "Draft", published: false)
    later = create_post(title: "Later", published: false)
    Posts::Save.call(later, attributes: { published_at: 3.days.from_now })
    at = later.reload.published_at
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ live.id, draft.id, later.id ] }
    assert_equal "Published 1 post. 1 was already live. 1 scheduled post was left as scheduled.", flash[:notice]
    assert_equal at, later.reload.published_at
  end

  test "a long title or reason is cut so the toast fits the session cookie" do
    long = "x" * 500
    bad = create_post(title: long, published: false)
    bad.update_columns(content_type: "not_registered")
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ bad.id ] }
    assert_response :see_other
    assert_operator flash[:alert].length, :<, 400
    assert_includes flash[:alert], "x" * 50
    assert_not_includes flash[:alert], "x" * 100
  end

  test "a 2 KB search string: no 500, the posts are trashed, the toast shows, and Undo is replaced by where to find them" do
    posts = Array.new(2) { |i| create_post(title: "Long q #{i}") }
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: posts.map(&:id), q: "q" * 2048 }
    assert_response :see_other
    assert posts.all? { |record| record.reload.trashed? }
    assert_equal "Moved 2 posts to the trash. Find them in the Trash.", flash[:notice]
    assert_nil flash[:undo]
    follow_redirect!
    assert_response :ok
    assert_select "#toasts .admin-toast", text: /Find them in the Trash\./
  end

  test "emptying the last page lands on the last page that exists; the index still reports a bad page" do
    insert_posts(51, published_at: nil, prefix: "Page")
    last = Post.order(:updated_at).first # the 51st row, alone on page 2
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: [ last.id ], page: "2", q: "Page" }
    assert_redirected_to "/cs-studio/posts?q=Page"
    # Two pages left, page 3 asked for after emptying page 2 completely:
    insert_posts(60, published_at: nil, prefix: "More")
    ids = Post.where("title ->> 'en' LIKE 'More%'").order(updated_at: :desc, id: :desc).offset(50).pluck(:id) # rows 51+ of the More list
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: ids, page: "2", q: "More" }
    assert_redirected_to "/cs-studio/posts?q=More"
    get "/cs-studio/posts", params: { page: "9" }
    assert_select "h3", text: "Nothing on this page"
  end

  # The `page = total_pages` branch: more than one page is left, so the
  # redirect names the last one rather than dropping `page` (which is only for
  # a list that fits on one).
  test "emptying the last page of a list that still has several lands on its last page" do
    insert_posts(101, published_at: nil, prefix: "Last")
    alone_on_page_three = Post.where("title ->> 'en' LIKE 'Last%'").order(updated_at: :desc, id: :desc).offset(100).pick(:id)
    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: [ alone_on_page_three ], page: "3", q: "Last" }
    assert_redirected_to "/cs-studio/posts?page=2&q=Last"
  end

  test "the toolbar counts of a content_types-scoped viewer count each readable post once" do
    2.times { |i| create_post(title: "Blog #{i}", tags: [ "a", "b" ]) }
    create_post(title: "Resume", content_type: "resume_entry")
    scoped = User.create!(email_address: "scoped-counts@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Blog readers")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => %w[blog] })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "own" => false, "content_types" => %w[blog] })
    AccessControl::Membership.create!(group: group, user: scoped)
    sign_in_as(scoped)
    get "/cs-studio/posts"
    assert_select "label[for=posts-scope-all] span.font-cs-mono", text: "2"
    assert_equal 2, row_titles.size
  end

  # --- POST /trash/restore_many ------------------------------------------------

  test "restore_many restores only trashed posts the viewer may restore, ignores the rest" do
    trashed = create_post(title: "In trash")
    kept = create_post(title: "Kept")
    page = create_page(title: "A page")
    as_owner { Trash::Move.call(trashed) }
    post "/cs-studio/trash/restore_many", params: { type: "post", ids: [ trashed.id, kept.id, page.id, 99_999_999, "abc" ] }
    assert_redirected_to "/cs-studio/posts"
    assert_equal "Restored 1 post. 4 posts were not found.", flash[:warning]
    assert_not trashed.reload.trashed?
    assert_equal 1, Audit::Event.where(action: "post.restored").count
  end

  test "restore_many through a forged id outside the viewer's scope changes nothing" do
    hidden = create_post(title: "Secret resume", content_type: "resume_entry")
    as_owner { Trash::Move.call(hidden) }
    scoped = User.create!(email_address: "blog-deleter@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Blog deleters")
    %w[posts.read posts.delete].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: { "content_types" => [ "blog" ] }) }
    AccessControl::Membership.create!(group: group, user: scoped)
    sign_in_as(scoped)
    post "/cs-studio/trash/restore_many", params: { type: "post", ids: [ hidden.id ] }
    assert_equal "Nothing was changed. 1 post was not found.", flash[:alert]
    assert hidden.reload.trashed?
  end

  test "restore_many answers 422 for another type, a non-array, or too many ids" do
    post "/cs-studio/trash/restore_many", params: { type: "page", ids: [ "1" ] }
    assert_response :unprocessable_entity
    post "/cs-studio/trash/restore_many", params: { type: "post", ids: "1" }
    assert_response :unprocessable_entity
    post "/cs-studio/trash/restore_many", params: { type: "post", ids: (1..201).map(&:to_s) }
    assert_response :unprocessable_entity
  end
end
