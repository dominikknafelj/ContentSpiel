require "test_helper"

# The New page and New post dialogs (design pass round 2, Task 15): where they
# are rendered, what `create` accepts (`page[page_type]`, `post[content_type]`),
# and how a refusal comes back -- a Turbo Stream replacing just the dialog's
# form for a Turbo submission, the standalone page for a plain request.
class Admin::NewRecordDialogsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @services = create_page(title: "Services")
    @outside = create_page(title: "Outside")
    @branch = create_page(title: "Branch")
    @inside = create_page(title: "Inside", parent: @branch)
  end

  # --- Layout ------------------------------------------------------------------

  test "every admin screen carries both dialog shells once, and no form" do
    sign_in_as(users(:one))
    get "/cs-studio/pages/#{@services.id}"

    assert_select "dialog#new-page-dialog", count: 1
    assert_select "dialog#new-post-dialog", count: 1
    assert_select "dialog#new-page-dialog turbo-frame#new-page-form-frame"
    assert_select "dialog#new-post-dialog turbo-frame#new-post-form-frame"
    assert_select "form#new-page-form", count: 0
    assert_select "form#new-post-form", count: 0
    assert_select "#new-page-inside", count: 0
  end

  test "the shells cost the same queries with 3 pages as with 30" do
    sign_in_as(users(:one))
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get "/cs-studio" }
      queries
    end
    count.call
    small = count.call
    27.times { |index| create_page(title: "Filler #{index}", parent: @services) }
    3.times { |index| ContentBlock.create!(owner: create_page(title: "List #{index}"), block_type: :post_list, position: 0, settings: { "content_type" => "blog" }) }
    assert_equal small, count.call, "the admin layout's query count grew with the number of pages or listing pages"
  end

  test "the form endpoint answers a frame request without the layout, inside the frame" do
    sign_in_as(users(:one))
    get "/cs-studio/pages/new", params: { parent_id: @services.id, title: "Team" }, headers: { "Turbo-Frame" => "new-page-form-frame" }

    assert_response :success
    assert_not_includes response.body, "<html"
    assert_select "turbo-frame#new-page-form-frame form#new-page-form"
    assert_select "#new-page-inside option[selected][value='#{@services.id}']"
    assert_select "input#new-page-title[value=Team]"

    get "/cs-studio/posts/new", params: { type: "now_update" }, headers: { "Turbo-Frame" => "new-post-form-frame" }
    assert_response :success
    assert_not_includes response.body, "<html"
    assert_select "turbo-frame#new-post-form-frame input[value=now_update][checked]"
  end

  test "the form endpoints cost the same queries with 3 pages as with 30, and with 1 listing page as with 4" do
    sign_in_as(users(:one))
    count = lambda do |path, frame|
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path, headers: { "Turbo-Frame" => frame } }
      queries
    end
    ContentBlock.create!(owner: @services, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    2.times { count.call("/cs-studio/pages/new", "new-page-form-frame"); count.call("/cs-studio/posts/new", "new-post-form-frame") }
    pages_small = count.call("/cs-studio/pages/new", "new-page-form-frame")
    posts_small = count.call("/cs-studio/posts/new", "new-post-form-frame")

    27.times { |index| create_page(title: "Filler #{index}", parent: @services) }
    3.times { |index| ContentBlock.create!(owner: create_page(title: "List #{index}"), block_type: :post_list, position: 0, settings: { "content_type" => "now_update" }) }

    assert_equal pages_small, count.call("/cs-studio/pages/new", "new-page-form-frame")
    assert_equal posts_small, count.call("/cs-studio/posts/new", "new-post-form-frame")
  end

  test "a viewer who can create neither gets neither dialog" do
    sign_in_as(users(:reader))
    get "/cs-studio/pages/#{@services.id}"

    assert_response :success
    assert_select "dialog#new-page-dialog", count: 0
    assert_select "dialog#new-post-dialog", count: 0
  end

  test "the no-JS pages render the form once, without the dialog around it" do
    sign_in_as(users(:one))

    get "/cs-studio/pages/new", params: { parent_id: @services.id }
    assert_response :success
    assert_select "dialog#new-page-dialog", count: 0
    assert_select "form#new-page-form", count: 1
    assert_select "dialog#new-page-dialog", count: 0
    assert_select "#new-page-inside option[selected][value='#{@services.id}']"

    get "/cs-studio/posts/new"
    assert_response :success
    assert_select "form#new-post-form", count: 1
    assert_select "dialog#new-post-dialog", count: 0
  end

  # --- Pages -------------------------------------------------------------------

  test "a landing page is created under the chosen parent, as a draft" do
    sign_in_as(users(:one))

    assert_difference "Page.count", 1 do
      post "/cs-studio/pages", params: { page: { title: "Team", parent_id: @services.id, page_type: "landing" } }
    end

    page = Page.order(:id).last
    assert_equal @services, page.parent
    assert page.landing?
    assert_not page.live?
    assert_redirected_to admin_page_path(page)
  end

  test "no page type means a standard page" do
    sign_in_as(users(:one))
    post "/cs-studio/pages", params: { page: { title: "Team", parent_id: @services.id } }

    assert Page.order(:id).last.standard?
  end

  test "a blank title answers 422 with a stream replacing the dialog's form, values kept" do
    sign_in_as(users(:one))

    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "", parent_id: @services.id, page_type: "landing" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=new-page-form]"
    assert_select "template form#new-page-form .admin-error-summary", text: /1 thing needs fixing/
    assert_select "template #new-page-inside option[selected][value='#{@services.id}']"
    assert_select "template #new-page-type option[selected][value=landing]"
  end

  test "a refused create without JavaScript re-renders the standalone page with the summary" do
    sign_in_as(users(:one))
    post "/cs-studio/pages", params: { page: { title: "", parent_id: @services.id } }

    assert_response :unprocessable_entity
    assert_select "form#new-page-form .admin-error-summary", text: /1 thing needs fixing/
    assert_select "dialog#new-page-dialog", count: 0
  end

  test "a taken slug comes back inside the dialog on the title" do
    sign_in_as(users(:one))
    post "/cs-studio/pages", params: { page: { title: "Services", parent_id: root_page.id } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "template .admin-error-summary a[href='#new-page-title']"
  end

  test "a forged page_type in an autosave is a validation failure, never a 500" do
    sign_in_as(users(:one))

    patch "/cs-studio/pages/#{@services.id}", params: { page: { page_type: "bogus" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "standard", @services.reload.page_type
  end

  test "a forged page type is a validation failure, never a 500" do
    sign_in_as(users(:one))

    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "Team", parent_id: @services.id, page_type: "bogus" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "template .admin-error-summary", text: /Page type/
  end

  test "Inside offers only the pages the viewer may create under" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @branch.id ] })
    sign_in_as(users(:editor_branch))
    # No parent_id (⌘K, the dashboard): the gate is "is there anywhere to create",
    # not "may they create under Home", which a branch editor may not.
    get "/cs-studio/pages/new", headers: { "Turbo-Frame" => "new-page-form-frame" }

    assert_response :success
    values = css_select("#new-page-inside option").map { |option| option["value"].to_i }
    assert_equal [ @branch.id, @inside.id ], values

    get "/cs-studio/pages/new"
    assert_response :success
    assert_select "form#new-page-form #new-page-inside option", count: 2
    assert_select "dialog#new-page-dialog", count: 0
  end

  test "a trashed page is never offered as a parent" do
    gone = create_page(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    sign_in_as(users(:one))
    get "/cs-studio/pages/new", headers: { "Turbo-Frame" => "new-page-form-frame" }

    assert_select "#new-page-inside option[value='#{@services.id}']"
    assert_select "#new-page-inside option[value='#{gone.id}']", count: 0
  end

  test "a parent trashed since the form loaded answers the form with a message on Inside, not a bare 404" do
    gone = create_page(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    sign_in_as(users(:one))

    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "Team", parent_id: gone.id } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=new-page-form] template .admin-error-summary a[href='#new-page-inside']", text: /Choose a page that still exists\./
    assert_select "template input#new-page-title[value=Team]"
  end

  test "a parent id that doesn't exist at all is still a 404" do
    sign_in_as(users(:one))
    post "/cs-studio/pages", params: { page: { title: "Team", parent_id: 0 } }, as: :turbo_stream
    assert_response :not_found
  end

  test "a parent outside the viewer's scope is 404, not 403" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @branch.id ] })
    sign_in_as(users(:editor_branch))

    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "Team", parent_id: @outside.id } }
    end
    assert_response :not_found
  end

  test "a readable parent the viewer may not create under is refused by the service, audited once" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @branch.id ] })
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.read", scope: {})
    sign_in_as(users(:editor_branch))

    assert_no_difference "Page.count" do
      assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
        post "/cs-studio/pages", params: { page: { title: "Team", parent_id: @outside.id } }, as: :turbo_stream
      end
    end
    assert_response :forbidden
  end

  # --- Posts -------------------------------------------------------------------

  test "a post is created as a draft of the chosen type" do
    sign_in_as(users(:one))

    assert_difference "Post.count", 1 do
      post "/cs-studio/posts", params: { post: { title: "Today", content_type: "now_update" } }
    end

    created = Post.order(:id).last
    assert_equal "now_update", created.content_type
    assert_not created.live?
    assert_redirected_to admin_post_path(created)
  end

  test "a blank post title answers 422 with a stream replacing the dialog's form, type kept" do
    sign_in_as(users(:one))

    assert_no_difference "Post.count" do
      post "/cs-studio/posts", params: { post: { title: "", content_type: "now_update" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=new-post-form]"
    assert_select "template form#new-post-form .admin-error-summary", text: /1 thing needs fixing/
    assert_select "template input[type=radio][value=now_update][checked]"
  end

  test "without JavaScript a refused post re-renders the standalone page" do
    sign_in_as(users(:one))
    post "/cs-studio/posts", params: { post: { title: "", content_type: "blog" } }

    assert_response :unprocessable_entity
    assert_select "form#new-post-form .admin-error-summary"
    assert_select "dialog#new-post-dialog", count: 0
  end

  test "the type picker offers only the types the viewer may create" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
    sign_in_as(users(:editor_branch))
    get "/cs-studio/posts/new", headers: { "Turbo-Frame" => "new-post-form-frame" }

    assert_equal [ "now_update" ], css_select("input[type=radio]").map { |radio| radio["value"] }
  end

  test "a type the viewer may not create is refused by the service, audited once" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
    sign_in_as(users(:editor_branch))

    assert_no_difference "Post.count" do
      assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
        post "/cs-studio/posts", params: { post: { title: "Forged", content_type: "blog" } }, as: :turbo_stream
      end
    end
    assert_response :forbidden
  end

  test "a type nothing lists says so in the URL line; a listed one shows its page's path" do
    sign_in_as(users(:one))
    get "/cs-studio/posts/new", headers: { "Turbo-Frame" => "new-post-form-frame" }
    assert_select "p[data-admin--new-record-target=url]", text: "Not listed on any page yet"
    assert_select "input[value=blog][data-path]", count: 0

    ContentBlock.create!(owner: @services, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    get "/cs-studio/posts/new", headers: { "Turbo-Frame" => "new-post-form-frame" }
    assert_select "input[value=blog][data-path='/services']"
    assert_select "p[data-admin--new-record-target=url]", text: "URL: /services/"
  end

  test "the New post form is forbidden when no type can be created" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "gone_type" ] })
    sign_in_as(users(:editor_branch))
    get "/cs-studio/posts/new", headers: { "Turbo-Frame" => "new-post-form-frame" }
    assert_response :forbidden
  end

  test "a site with no page at all still offers New page, and creating makes the home page" do
    [ ContentBlock, PublicPath, PageHierarchy, Page ].each(&:delete_all)
    sign_in_as(users(:one))

    get "/cs-studio"
    assert_select "dialog#new-page-dialog", count: 1

    get "/cs-studio/pages/new", headers: { "Turbo-Frame" => "new-page-form-frame" }
    assert_select "#new-page-inside", count: 0
    assert_select "[data-admin--new-record-target=note]", text: "Created as the home page."

    assert_difference "Page.count", 1 do
      post "/cs-studio/pages", params: { page: { title: "Home" } }
      assert_response :see_other, css_select(".admin-error-summary").map(&:text).join(" ").squish
    end
    assert_nil Page.order(:id).last.parent_id
  end

  test "the Trash restore picker offers a branch editor the branch root too" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @branch.id ] })
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.delete", scope: { "page_ids" => [ @branch.id ] })
    gone = create_page(title: "Gone", parent: @inside)
    as_owner { Trash::Move.call(gone) }
    as_owner { Trash::Move.call(@inside) } # its parent is trashed too: the row needs a new parent
    sign_in_as(users(:editor_branch))
    get "/cs-studio/trash"

    values = css_select("select[name=parent_id] option").map { |option| option["value"].to_i }
    assert_includes values, @branch.id
  end

  test "a tree plus for a page trashed in another tab loads the form with the default parent" do
    gone = create_page(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    sign_in_as(users(:one))

    get "/cs-studio/pages/new", params: { parent_id: gone.id }, headers: { "Turbo-Frame" => "new-page-form-frame" }
    assert_response :success
    assert_select "#new-page-inside option[selected][value='#{root_page.id}']"

    get "/cs-studio/pages/new", params: { parent_id: 0 }, headers: { "Turbo-Frame" => "new-page-form-frame" }
    assert_response :not_found
  end

  test "the New post form instance is built once per request" do
    sign_in_as(users(:one))
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("post_list") || payload[:sql].match?(/FROM "content_blocks"/) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/cs-studio/posts/new", headers: { "Turbo-Frame" => "new-post-form-frame" }
    end
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "content_blocks"/) }
  end

  test "the database allows one root page, and a lost race fails like the validation" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Page.new(page_type: :standard, title: "Second root", slug: "second-root").tap { |page| page.save(validate: false) }
    end

    PublicPath.delete_all # so nothing but the root rule can refuse the second root
    racer = Page.new
    racer.define_singleton_method(:only_one_root_page) { } # both creates passed the validation
    result = as_owner { Pages::Save.call(racer, attributes: { published: false }, translations: { "en" => { title: "Racer" } }) }

    assert_not result.ok?
    assert_includes result.record.errors.full_messages, "a root page already exists"
  end
end
