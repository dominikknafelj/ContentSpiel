require "test_helper"

# CS Studio enforcement (access-control design spec §3.3 "Scopes for
# reading", §3.4 "Controllers", §5 "Everywhere"): which modules each group
# sees, 403 for an area without its permission, 404 -- never 403 -- for a
# record outside the actor's read scope (Review Focus 2), lists/pickers/tree
# narrowed to what the actor may read, action buttons only when allowed, and
# the "View only" editor for a record that's readable but not editable.
#
# Fixture users (test/fixtures/users.yml): `two` is in Admin, `author` in
# Author (own posts; every post and page readable), `reader` in Read only,
# `editor_branch` in the grant-less "Branch editors" group -- the branch
# grants it needs are created per test against pages built here.
class Admin::AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = root_page
    @outside = create_page(title: "Outside")
    @branch = create_page(title: "Branch")
    @inside = create_page(title: "Inside", parent: @branch)

    @own_post = create_post(title: "Own post", published: false)
    @own_post.update_column(:author_id, users(:author).id)
    @other_post = create_post(title: "Other post", published: false)
    @other_post.update_column(:author_id, users(:two).id)
  end

  # --- Sidebar ---------------------------------------------------------------

  test "each group sees only the modules it can open" do
    expectations = {
      # Media library Task 7: the Media module needs only `media.upload`
      # (design spec §6, `Admin::BaseController::MODULES`), which `two`
      # (Admin, every permission) and `author` (`media.upload` is one of
      # its own seeded grants, test/fixtures/access_control/grants.yml)
      # both hold, and `reader` (Read only) doesn't. Trash (trash spec §6)
      # opens for any one of the rights that act on a trashed item, so
      # `author`'s `media.upload` is enough -- its own trashed images.
      users(:two) => [ "Dashboard", "Pages", "Posts", "Media", "Translations", "Tags", "Mind graph", "Trash", "Users", "Groups", "Settings", "AI assistant", "System status", "Audit log" ],
      users(:author) => [ "Dashboard", "Pages", "Posts", "Media", "Translations", "Mind graph", "Trash", "AI assistant" ],
      users(:reader) => [ "Dashboard", "Pages", "Posts", "Translations", "Mind graph", "AI assistant" ]
    }

    expectations.each do |user, labels|
      sign_in_as(user)
      get "/cs-studio/api_tokens"
      assert_response :success
      assert_equal labels, sidebar_labels, "sidebar for #{user.email_address}"
      sign_out
    end
  end

  test "a branch editor without post permissions sees no Posts or Mind graph" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/api_tokens"

    assert_equal [ "Dashboard", "Pages", "Translations", "AI assistant" ], sidebar_labels
  end

  # `AccessControl.holds?` doesn't count a grant whose named content types are
  # all unregistered: it reaches no post, so its holder gets no Posts entry
  # (and the module's own gate answers 403) instead of an entry leading to an
  # empty list. A live type beside the removed one brings both back.
  test "a posts.read grant naming only removed content types gives no Posts entry and a 403 at /posts; a live type beside it brings both back" do
    grant = AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.read", scope: { "content_types" => [ "retired_type" ] })
    sign_in_as(users(:editor_branch))

    get "/cs-studio/api_tokens"
    assert_not_includes sidebar_labels, "Posts"
    assert_not_includes sidebar_labels, "Mind graph"
    get "/cs-studio/posts"
    assert_response :forbidden
    assert_select "nav[aria-label='Modules']"
    assert_select "h1", text: "No access"

    grant.update!(scope: { "content_types" => %w[blog retired_type] })
    get "/cs-studio/api_tokens"
    assert_includes sidebar_labels, "Posts"
    get "/cs-studio/posts"
    assert_response :success
  end

  # --- Area access -------------------------------------------------------------

  test "an author opening an admin area gets the 403 page in the CS Studio layout" do
    sign_in_as(users(:author))

    %w[/cs-studio/users /cs-studio/users/new /cs-studio/tags /cs-studio/settings /cs-studio/system_status].each do |path|
      get path
      assert_response :forbidden, path
      assert_select "nav[aria-label='Modules']"
      assert_select "h1", text: "No access"
    end

    # The old Languages screen's URL is a redirect to the Settings card now.
    get "/cs-studio/settings/languages"
    assert_response :moved_permanently
    follow_redirect!
    assert_response :forbidden
    assert_select "h1", text: "No access"
  end

  test "an area write without the permission is refused before reaching the service" do
    sign_in_as(users(:author))

    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: { email_address: "new@example.com", password: "password12345", password_confirmation: "password12345" } }
    end
    assert_response :forbidden
  end

  test "posts need posts.read, and new posts need posts.create" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))
    get "/cs-studio/posts"
    assert_response :forbidden

    sign_in_as(users(:reader))
    get "/cs-studio/posts/new"
    assert_response :forbidden
  end

  # Dashboard spec Task 2: `BaseController::MODULES` now lists Dashboard
  # first with `permission: nil`, so `first_admin_module_path` -- the Pages
  # index's own fallback for someone without `pages.read` -- always resolves
  # to it, whatever else the actor can or can't open.
  test "the pages index sends a user without pages.read to the dashboard" do
    access_control_grants(:read_only_pages_read).destroy!
    sign_in_as(users(:reader))

    get "/cs-studio/pages"

    assert_redirected_to "/cs-studio"
  end

  # --- Out-of-scope records: 404, not 403 (Review Focus 2) -------------------

  test "an author whose reads are limited to their own posts gets 404 for someone else's" do
    narrow_author_reads_to_own
    sign_in_as(users(:author))

    get "/cs-studio/posts/#{@other_post.id}"
    assert_response :not_found
    assert_select "form[action='/cs-studio/posts/#{@other_post.id}']", count: 0

    patch "/cs-studio/posts/#{@other_post.id}", params: { post: { title: "Hijacked" } }, as: :turbo_stream
    assert_response :not_found
    assert_equal "Other post", @other_post.reload.title

    get "/cs-studio/posts/#{@own_post.id}"
    assert_response :success
  end

  test "a branch editor gets 404 for a page outside the branch, in CS Studio and in preview" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages/#{@outside.id}"
    assert_response :not_found

    post "/cs-studio/pages/#{@outside.id}/content_blocks", params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :not_found

    get "/preview/outside"
    assert_response :not_found

    get "/preview/branch/inside"
    assert_response :success
  end

  test "a page move naming a page outside the scope is not found" do
    grant_branch("pages.edit", "pages.move", "pages.create")
    sign_in_as(users(:editor_branch))

    patch "/cs-studio/tree", params: { page_id: @outside.id, parent_id: @branch.id, position: 0 }, as: :turbo_stream

    assert_response :not_found
    assert_equal @root, @outside.reload.parent
  end

  # --- Lists and the tree ------------------------------------------------------

  test "the posts list shows only readable posts" do
    narrow_author_reads_to_own
    sign_in_as(users(:author))

    get "/cs-studio/posts"

    assert_response :success
    assert_includes response.body, "Own post"
    assert_not_includes response.body, "Other post"
  end

  test "the tree greys out context ancestors, unlinked and without actions, and hides the rest" do
    with_locales(%w[en de], default: "en")
    # The context-only Home has an outdated German field: its count must stay
    # hidden (a number would hint at a page the viewer can't open).
    assert Pages::Save.call(@root, translations: { "de" => { title: "Start" } }).ok?
    assert Pages::Save.call(@root, translations: { "en" => { title: "Home!" } }).ok?
    grant_branch("pages.edit", "pages.create")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages/#{@inside.id}"
    assert_response :success

    assert_select "turbo-frame#tree li[data-page-id='#{@root.id}'][data-context-only]" do |nodes|
      row = nodes.first.at_css("> div")
      assert_nil row.at_css("a"), "a context-only node has no link or actions"
      assert_nil row.at_css(".admin-tree-node__handle")
      assert_includes row.text, "Home"
      assert_equal 1, Translations::StateIndex.counts_for([ @root.reload ]).values.first["de"][:outdated]
      assert_select nodes.first, "> div span.text-meta[title='You can’t open this page']"
      assert_nil row.at_css("[data-translation-marker]"), "a context-only row shows no counts"
    end
    assert_select "turbo-frame#tree li[data-page-id='#{@branch.id}']:not([data-context-only]) a[href='/cs-studio/pages/#{@branch.id}']"
    assert_select "turbo-frame#tree li[data-page-id='#{@inside.id}'] a[href='/cs-studio/pages/#{@inside.id}']"
    assert_select "turbo-frame#tree li[data-page-id='#{@outside.id}']", count: 0
  end

  test "/pages for a viewer who reads only a deep branch is the empty state, not a 404 or a redirect" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages"

    assert_response :success
    assert_select "h2, p, div", text: "Choose a page from the tree"
    assert_select "turbo-frame#tree li[data-page-id='#{@inside.id}']"
  end

  test "rendering the tree as a branch editor costs the same queries however many pages it shows" do
    grant_branch("pages.edit", "pages.create", "pages.move")
    sign_in_as(users(:editor_branch))
    3.times { |index| create_page(title: "Small #{index}", parent: @inside) }

    get "/cs-studio/pages/#{@inside.id}" # warm up whatever a first request loads once
    small = count_queries { get "/cs-studio/pages/#{@inside.id}" }
    assert_response :success

    12.times { |index| create_page(title: "Large #{index}", parent: @inside) }
    large = count_queries { get "/cs-studio/pages/#{@inside.id}" }

    assert_select "turbo-frame#tree li.admin-tree-node", count: 18
    assert_equal small, large, "the tree ran a query per page"
  end

  test "the tree shows the move handle and the add-child link only where allowed" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages/#{@inside.id}"

    assert_select "li[data-page-id='#{@inside.id}'] > div .admin-tree-node__handle", count: 0
    assert_select "li[data-page-id='#{@inside.id}'] > div a[aria-label^='Add a page under']", count: 0

    sign_in_as(users(:two))
    get "/cs-studio/pages/#{@inside.id}"

    assert_select "li[data-page-id='#{@inside.id}'] > div .admin-tree-node__handle"
    assert_select "li[data-page-id='#{@inside.id}'] > div a[aria-label^='Add a page under']"
  end

  # --- Pickers ------------------------------------------------------------------

  test "link-target search returns only readable targets" do
    grant_branch("pages.edit")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/link_targets"

    results = response.parsed_body
    assert_equal [ [ "page", @branch.id ], [ "page", @inside.id ] ], results.map { |r| [ r["type"], r["id"] ] }.sort
  end

  test "related-post search returns only readable posts" do
    narrow_author_reads_to_own
    sign_in_as(users(:author))

    get "/cs-studio/link_targets", params: { type: "post", q: "post" }

    assert_equal [ @own_post.id ], response.parsed_body.map { |r| r["id"] }
  end

  test "the mind graph has only readable nodes, and no edge to an unreadable one" do
    narrow_author_reads_to_own
    second_own = create_post(title: "Second own")
    second_own.update_column(:author_id, users(:author).id)
    PostRelation.create!(post: @own_post, related_post: @other_post)
    PostRelation.create!(post: @own_post, related_post: second_own)
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph/data"

    data = response.parsed_body
    assert_equal [ @own_post.id, second_own.id ].sort, data["nodes"].map { |node| node["id"] }.sort
    assert_equal [ { "source" => @own_post.id, "target" => second_own.id, "kind" => "related" } ], data["edges"]
  end

  test "the post editor names no related post the actor can't read" do
    narrow_author_reads_to_own
    PostRelation.create!(post: @own_post, related_post: @other_post)
    pointing_here = create_post(title: "Pointing here")
    PostRelation.create!(post: pointing_here, related_post: @own_post)
    sign_in_as(users(:author))

    get "/cs-studio/posts/#{@own_post.id}"

    assert_response :success
    assert_select "[data-field-name='related_post_ids']" do
      assert_select "li[data-chip-value='#{@other_post.id}']", count: 0
      assert_select "input[type=hidden][value='#{@other_post.id}']", count: 0
      assert_select "a[href='/cs-studio/posts/#{@other_post.id}']", count: 0
      assert_select "p", text: "+1 related post you can’t open (kept)"
    end
    assert_no_match(/data-chip-value="#{@other_post.id}"/, response.body)
    assert_not_includes response.body, "Other post"
    assert_not_includes response.body, "Pointing here" # "Also related from"
  end

  # Task 7 review ruling: the picker never submits a relation it didn't
  # render, so `Posts::Save` keeps relations to unreadable posts whatever
  # the list says -- including `[""]` (the sentinel alone, "clear").
  test "saving the related posts keeps a relation to a post the actor can't read" do
    narrow_author_reads_to_own
    second_own = create_post(title: "Second own", published: false)
    second_own.update_column(:author_id, users(:author).id)
    PostRelation.create!(post: @own_post, related_post: @other_post)
    sign_in_as(users(:author))

    patch "/cs-studio/posts/#{@own_post.id}", params: { post: { related_post_ids: [ "", second_own.id.to_s ] } }, as: :turbo_stream
    assert_response :success
    assert_equal [ @other_post.id, second_own.id ].sort, PostRelation.where(post: @own_post).pluck(:related_post_id).sort

    patch "/cs-studio/posts/#{@own_post.id}", params: { post: { related_post_ids: [ "" ] } }, as: :turbo_stream
    assert_response :success
    assert_equal [ @other_post.id ], PostRelation.where(post: @own_post).pluck(:related_post_id)
  end

  # --- Fix round 1 -------------------------------------------------------------

  test "the editor shows no title for a link to a page the actor can't read (I1)" do
    block = ContentBlocks::Save.call(@inside.content_blocks.new, attributes: { block_type: "rich_text" },
      translations: { "en" => { body: link_doc("page", @outside.id) } }).record
    assert block.persisted?
    grant_branch("pages.edit", "pages.publish")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages/#{@inside.id}"

    assert_response :success
    titles = JSON.parse(css_select("[data-admin--rich-text--editor-link-titles-value]").first["data-admin--rich-text--editor-link-titles-value"])
    assert_equal({ "page:#{@outside.id}" => "A page you can't open" }, titles)
    # Whole word: the toolbar's Insert menu carries a `closeOutside` action.
    assert_no_match(/\bOutside\b/, response.body)

    # The link was already there, so editing the block around it still saves.
    patch "/cs-studio/pages/#{@inside.id}/content_blocks/#{block.id}",
      params: { block: { body: link_doc("page", @outside.id, text: "still here").to_json } }, as: :turbo_stream
    assert_response :success
  end

  test "adding a link to an unreadable page fails exactly like a link to a missing one (I1)" do
    block = ContentBlocks::Save.call(@inside.content_blocks.new, attributes: { block_type: "rich_text" }).record
    grant_branch("pages.edit", "pages.publish")
    sign_in_as(users(:editor_branch))
    path = "/cs-studio/pages/#{@inside.id}/content_blocks/#{block.id}"

    error_id = Admin::Ui::FieldComponent.error_id(Admin::EditorScreen::BlockCardComponent.error_prefix(block), "body")
    unreadable, missing = [ @outside.id, Page.maximum(:id) + 1000 ].map do |target_id|
      patch path, params: { block: { body: link_doc("page", target_id).to_json } }, as: :turbo_stream
      assert_response :unprocessable_entity
      Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='#{error_id}']").text.squish
    end

    assert_includes unreadable, "internalLink.id is invalid"
    assert_equal missing, unreadable

    patch path, params: { block: { body: link_doc("page", @branch.id).to_json } }, as: :turbo_stream
    assert_response :success
  end

  test "previewing a readable post listed on an unreadable page is not found (I2)" do
    blog = create_page(title: "Blog")
    ContentBlocks::Save.call(blog.content_blocks.new, attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    publish_changes(blog)
    Posts::Save.call(@other_post, attributes: { published: true })
    grant_branch("pages.read")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.read", scope: {})
    sign_in_as(users(:editor_branch))

    get "/preview/blog/other-post"
    assert_response :not_found

    sign_in_as(users(:two))
    get "/preview/blog/other-post"
    assert_response :success
  end

  test "a preview redirect from an old address checks the target is readable first (M2)" do
    Pages::Save.call(@outside, translations: { "en" => { slug: "elsewhere" } })
    grant_branch("pages.read")
    sign_in_as(users(:editor_branch))

    get "/preview/outside"
    assert_response :not_found

    sign_in_as(users(:two))
    get "/preview/outside"
    assert_redirected_to "/preview/elsewhere"
  end

  test "an autosave refused by an area check answers the 403 save-status stream (M5)" do
    tag = Tag.create!(name: "news")
    sign_in_as(users(:author))

    patch "/cs-studio/tags/#{tag.id}", params: { tag: { name: "hijacked" } }, as: :turbo_stream

    assert_response :forbidden
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select_in_stream "tag-#{tag.id}-save-status", /you don.t have permission/
    assert_equal "news", tag.reload.name
  end

  test "creating a page under an unreadable parent is not found, not the homepage (M7)" do
    grant_branch("pages.create")
    sign_in_as(users(:editor_branch))

    assert_no_difference -> { Page.count } do
      post "/cs-studio/pages", params: { page: { title: "Sneaky", parent_id: @outside.id } }
    end
    assert_response :not_found

    assert_difference -> { @branch.children.count }, 1 do
      post "/cs-studio/pages", params: { page: { title: "Fine", parent_id: @branch.id } }
    end
  end

  # --- Buttons ------------------------------------------------------------------

  test "publish, delete and add-block are absent for a reader, present for an admin" do
    sign_in_as(users(:reader))
    get "/cs-studio/pages/#{@outside.id}"

    assert_response :success
    assert_select "button, input[type=submit]", text: /Publish|Unpublish|Move to trash/, count: 0
    assert_select "dialog[id^=schedule-]", count: 0
    assert_select "#block-picker-end", count: 0

    sign_in_as(users(:two))
    get "/cs-studio/pages/#{@outside.id}"

    assert_select "button", text: "Unpublish"
    assert_select "button", text: "Move to trash"
    assert_select "#block-picker-end"
  end

  test "an author editing their own draft post gets neither Publish nor Move to trash" do
    sign_in_as(users(:author))

    get "/cs-studio/posts/#{@own_post.id}"

    assert_response :success
    assert_select "form[data-controller~='admin--saving--autosave']"
    assert_select "button, input[type=submit]", text: /Publish|Move to trash/, count: 0
  end

  test "new posts offer only the content types the author may create" do
    access_control_grants(:author_posts_create).update!(scope: { "content_types" => [ "blog" ] })
    sign_in_as(users(:author))

    get "/cs-studio/posts/new"

    assert_response :success
    assert_select "input[type=radio][name='post[content_type]']", count: 1
    assert_select "input[type=radio][name='post[content_type]'][value='blog']"
  end

  # --- View only ---------------------------------------------------------------

  test "a readable but not editable post renders view only: badge, disabled fields, no autosave" do
    sign_in_as(users(:reader))

    get "/cs-studio/posts/#{@other_post.id}"

    assert_response :success
    assert_select "[data-view-only]", text: "View only"
    assert_select "[data-controller~='admin--saving--autosave']", count: 0
    assert_select "form fieldset[disabled]"
  end

  test "a published post the author may edit but not publish is view only" do
    Posts::Save.call(@own_post, attributes: { published: true })
    sign_in_as(users(:author))

    get "/cs-studio/posts/#{@own_post.id}"

    assert_select "[data-view-only]", text: "View only"
    assert_select "[data-controller~='admin--saving--autosave']", count: 0
  end

  test "a readable but not editable page renders its settings and blocks view only" do
    ContentBlocks::Save.call(@outside.content_blocks.new, attributes: { block_type: "rich_text" })
    sign_in_as(users(:reader))

    get "/cs-studio/pages/#{@outside.id}"

    assert_select "[data-view-only]", text: "View only"
    assert_select "[data-controller~='admin--saving--autosave']", count: 0
    assert_select ".admin-block-card fieldset[disabled]"
    assert_select ".admin-block-card__handle", count: 0
    assert_select ".admin-block-card__menu", count: 0
  end

  test "a forged autosave from a reader is refused with 403 and one access.denied event" do
    sign_in_as(users(:reader))

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      patch "/cs-studio/posts/#{@other_post.id}", params: { post: { title: "Forged" } }, as: :turbo_stream
    end

    assert_response :forbidden
    assert_includes response.body, "post-save-status"
    assert_equal "Other post", @other_post.reload.title
  end

  test "a denied publish renders the 403 page with the reason" do
    sign_in_as(users(:author))

    post "/cs-studio/posts/#{@own_post.id}/publish"

    assert_response :forbidden
    assert_includes CGI.unescapeHTML(response.body), "You don't have permission to"
    assert_nil @own_post.reload.published_at
  end

  # Final fix wave (Important 1): a "Publishers" group (read + publish, no
  # edit) sees the header's publish buttons and they work.
  test "a publisher without edit publishes and unpublishes through the header buttons" do
    group = AccessControl::Group.create!(name: "Publishers")
    %w[posts.read posts.publish pages.read pages.publish].each do |key|
      AccessControl::Grant.create!(group: group, permission: key, scope: {})
    end
    AccessControl::Membership.create!(group: group, user: users(:reader))
    Pages::Save.call(@outside, attributes: { published: false })
    sign_in_as(users(:reader))

    get "/cs-studio/posts/#{@other_post.id}"
    assert_select "[data-view-only]", text: "View only"
    assert_select "button", text: "Publish"
    post "/cs-studio/posts/#{@other_post.id}/publish"
    assert_redirected_to "/cs-studio/posts/#{@other_post.id}"
    assert @other_post.reload.live?
    post "/cs-studio/posts/#{@other_post.id}/schedule", params: { published_at: 2.days.from_now.iso8601 }
    assert @other_post.reload.published_at.future?
    post "/cs-studio/posts/#{@other_post.id}/unpublish"
    assert_nil @other_post.reload.published_at

    get "/cs-studio/pages/#{@outside.id}"
    assert_select "button", text: "Publish"
    post "/cs-studio/pages/#{@outside.id}/publish"
    assert @outside.reload.live?
    post "/cs-studio/pages/#{@outside.id}/unpublish"
    assert_nil @outside.reload.published_at

    patch "/cs-studio/posts/#{@other_post.id}", params: { post: { title: "Renamed" } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal "Other post", @other_post.reload.title
  end

  # Final fix wave (Minor 10): the page editor checks many permissions on
  # its one page (header buttons, settings, every block card); its branch
  # is loaded once, not once per check.
  test "the page editor loads a branch-scoped page's branch once" do
    grant_branch("pages.read", "pages.edit", "pages.publish", "pages.delete", "pages.create")
    3.times { ContentBlocks::Save.call(@inside.content_blocks.new, attributes: { block_type: "rich_text" }) }
    sign_in_as(users(:editor_branch))

    statements = []
    collect = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(collect, "sql.active_record") { get "/cs-studio/pages/#{@inside.id}" }

    assert_response :success
    branch_lookups = statements.grep(/FROM "page_hierarchies"/).grep(/"descendant_id" = /)
    assert_operator branch_lookups.size, :<=, 1, branch_lookups.join("\n")
  end

  # --- Carry-overs ---------------------------------------------------------------

  test "a denied media upload is a 403 with JSON errors" do
    sign_in_as(users(:reader))

    assert_no_difference -> { Media::Asset.count } do
      post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }
    end

    assert_response :forbidden
    assert_match(/permission/, response.parsed_body["errors"].first)
  end

  test "a denied block delete or reorder answers 403 and changes nothing" do
    first = ContentBlocks::Save.call(@outside.content_blocks.new, attributes: { block_type: "rich_text" }).record
    second = ContentBlocks::Save.call(@outside.content_blocks.new, attributes: { block_type: "rich_text" }).record
    sign_in_as(users(:reader))

    delete "/cs-studio/pages/#{@outside.id}/content_blocks/#{first.id}", as: :turbo_stream
    assert_response :forbidden
    assert ContentBlock.exists?(first.id)
    assert_includes response.body, "content-blocks-alert"

    patch "/cs-studio/pages/#{@outside.id}/content_blocks/reorder", params: { ids: [ second.id, first.id ] }, as: :turbo_stream
    assert_response :forbidden
    assert_equal [ first.id, second.id ], @outside.content_blocks.reload.ids
  end

  test "a failed block delete that isn't a denial reports the error instead of claiming success" do
    block = ContentBlocks::Save.call(@outside.content_blocks.new, attributes: { block_type: "rich_text" }).record
    sign_in_as(users(:two))

    failing = ->(*, **) { ApplicationService::Result.failure(block, [ "Nope" ]) }
    with_singleton_override(ContentBlocks::Destroy, :call, failing) do
      delete "/cs-studio/pages/#{@outside.id}/content_blocks/#{block.id}", as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Nope"
  end

  test "API tokens: everyone sees their own, tokens.manage sees everyone's" do
    ApiToken.generate!(users(:two), group: access_control_groups(:admin))
    own, = ApiToken.generate!(users(:reader), group: access_control_groups(:read_only))
    others, = ApiToken.generate!(users(:two), group: access_control_groups(:admin))

    sign_in_as(users(:reader))
    get "/cs-studio/api_tokens"
    assert_select "tr[id^='api_token_']", count: 1
    assert_select "tr#api_token_#{own.id}"

    delete "/cs-studio/api_tokens/#{others.id}"
    assert_response :not_found
    assert_nil others.reload.revoked_at

    sign_in_as(users(:two))
    get "/cs-studio/api_tokens"
    assert_select "tr[id^='api_token_']", count: 3
  end

  private

  def link_doc(type, id, text: "click")
    { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => text, "marks" => [ { "type" => "internalLink", "attrs" => { "type" => type, "id" => id } } ] }
    ] } ] }
  end

  def grant_branch(*keys, root: @branch)
    keys.each do |key|
      AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ root.id ] })
    end
  end

  # The seeded Author group reads every post -- through `posts.read`, and
  # through its unscoped `posts.create` too, since any write key implies
  # `read` within its own scope (design spec §3.3 "Implication"). These
  # tests need an author whose reads stop at their own posts, so "someone
  # else's post" is out of scope: both grants become `own`.
  def narrow_author_reads_to_own
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
  end

  def sidebar_labels
    css_select("nav[aria-label='Modules'] section a").map { |link| link.at_css("span:not([data-badge])").text.strip }
  end

  # Every SQL statement the block issues, answered from the query cache or
  # not: the test's shared connection keeps its query cache across
  # requests, so "not cached" would under-count a repeat request -- but a
  # per-row query shows up here either way.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
