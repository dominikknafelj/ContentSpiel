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

  test "every admin screen carries both dialogs once, for someone who may create" do
    sign_in_as(users(:one))
    get "/cs-studio/pages/#{@services.id}"

    assert_select "dialog#new-page-dialog", count: 1
    assert_select "dialog#new-post-dialog", count: 1
    assert_select "dialog#new-page-dialog form#new-page-form[action='/cs-studio/pages']"
    assert_select "dialog#new-post-dialog form#new-post-form[action='/cs-studio/posts']"
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
    get "/cs-studio/pages/#{@inside.id}"

    values = css_select("dialog#new-page-dialog #new-page-inside option").map { |option| option["value"].to_i }
    assert_equal [ @branch.id, @inside.id ], values
  end

  test "a trashed page is never offered as a parent, and forging it is a 404" do
    gone = create_page(title: "Gone")
    as_owner { Trash::Move.call(gone) }
    sign_in_as(users(:one))
    get "/cs-studio/pages/#{@services.id}"

    assert_select "#new-page-inside option[value='#{gone.id}']", count: 0
    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "Team", parent_id: gone.id } }
    end
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
    get "/cs-studio/pages/#{@services.id}"

    assert_equal [ "now_update" ], css_select("dialog#new-post-dialog input[type=radio]").map { |radio| radio["value"] }
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
    get "/cs-studio/pages/#{@services.id}"
    assert_select "dialog#new-post-dialog p[data-admin--new-record-target=url]", text: "Not listed on any page yet"
    assert_select "dialog#new-post-dialog input[value=blog][data-path]", count: 0

    ContentBlock.create!(owner: @services, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    get "/cs-studio/pages/#{@services.id}"
    assert_select "dialog#new-post-dialog input[value=blog][data-path='/services']"
    assert_select "dialog#new-post-dialog p[data-admin--new-record-target=url]", text: "URL: /services/"
  end
end
