require "test_helper"

class AvoAccessTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "unauthenticated visitors are redirected away from /avo" do
    get "/avo"

    assert_redirected_to_sign_in
  end

  test "unauthenticated visitors are redirected away from an Avo resource index" do
    get "/avo/resources/posts"

    assert_redirected_to_sign_in
  end

  test "an authenticated user can reach /avo" do
    sign_in

    get "/avo"

    # Avo's root bounces to the first registered resource index.
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "an authenticated user can reach every registered resource index" do
    sign_in

    %w[posts tags site_settings api_tokens pages content_blocks].each do |resource|
      get "/avo/resources/#{resource}"

      assert_response :success, "expected /avo/resources/#{resource} to render"
    end
  end

  # Index pages render no association panels and no form, so they exercise
  # almost none of a resource's field list. Show and New are where a field
  # pointing at an unregistered resource, or a non-nullable disabled column,
  # actually blows up -- so both get their own coverage below.
  test "an authenticated user can reach the show page of every registered resource" do
    sign_in

    show_records.each do |resource, record|
      get "/avo/resources/#{resource}/#{record.to_param}"

      assert_response :success, "expected /avo/resources/#{resource}/#{record.to_param} to render"
    end
  end

  # `has_many` panels are lazy turbo frames: the show page only renders the
  # frame tag, and the panel body is fetched separately from the associations
  # controller. A field naming a model with no Avo resource renders a perfectly
  # fine frame tag and only blows up when that frame is fetched -- so follow
  # every frame the show pages actually advertise rather than a hardcoded list.
  test "every has_many panel advertised by a show page loads" do
    sign_in

    frames = show_records.flat_map do |resource, record|
      get "/avo/resources/#{resource}/#{record.to_param}"
      assert_response :success
      lazy_frame_sources(response.body)
    end

    assert_not_empty frames, "expected the show pages to advertise at least one association panel"

    frames.each do |src|
      get src

      assert_response :success, "expected the association panel at #{src} to render"
    end
  end

  test "an authenticated user can reach the new page of every resource that allows creation" do
    sign_in

    %w[posts tags site_settings users pages content_blocks].each do |resource|
      get "/avo/resources/#{resource}/new"

      assert_response :success, "expected /avo/resources/#{resource}/new to render"
    end
  end

  # The User resource is the only in-product way to add an admin (db/seeds.rb
  # is development-only), so its New form has to actually work -- with only
  # email_address exposed, has_secure_password would reject every submission.
  test "a new user can be created through the Avo form" do
    sign_in

    get "/avo/resources/users/new"
    assert_response :success

    assert_difference -> { User.count }, 1 do
      post "/avo/resources/users", params: { user: {
        email_address: "second-admin@example.com",
        password: "another-password",
        password_confirmation: "another-password"
      } }
    end

    assert_response :redirect
    assert User.find_by(email_address: "second-admin@example.com").authenticate("another-password")
  end

  # The page tree is the site's whole structure, so its New form has to work
  # end to end rather than merely render: the translated fields are per-locale
  # accessors, the parent picker is what attaches the page to the tree, and the
  # inline block editor rides along on the same submission. What each of those
  # does in detail is AvoPageEditingTest's business.
  test "an authenticated user can view and create a Page" do
    sign_in
    root = Page.create!(title: "Home")

    get "/avo/resources/pages"
    assert_response :success

    get "/avo/resources/pages/new"
    assert_response :success

    assert_difference -> { Page.count }, 1 do
      post "/avo/resources/pages", params: { page: {
        parent_id: root.id,
        page_type: "standard",
        title_en: "About",
        slug_en: "about",
        content_blocks_attributes: {
          "0" => { block_type: "rich_text", position: "0", body_en: "<p>Hi</p>" }
        }
      } }
    end

    assert_response :redirect

    created = Page.find_by!(parent_id: root.id)
    assert_equal "About", created.title_en
    assert_equal "/about", created.full_path(:en)
    assert_equal [ "rich_text" ], created.content_blocks.map(&:block_type)
  end

  # The password fields render on Edit too, so leaving them blank there must not
  # wipe the existing digest and lock the user out.
  test "editing a user without retyping the password leaves the password intact" do
    sign_in

    put "/avo/resources/users/#{@user.id}", params: { user: {
      email_address: "renamed@example.com", password: "", password_confirmation: ""
    } }

    assert_response :redirect
    assert_equal "renamed@example.com", @user.reload.email_address
    assert @user.authenticate("password123")
  end

  # ApiTokens are minted by ApiToken.generate! (the bcrypt digest is never
  # hand-entered), so the resource has no usable New form. The route must turn
  # the request away rather than 500 on the NOT NULL token_digest column.
  test "creating an api token through Avo is turned away instead of crashing" do
    sign_in

    get "/avo/resources/api_tokens/new"
    assert_redirected_to_avo_path "/avo/resources/api_tokens"

    assert_no_difference -> { ApiToken.count } do
      post "/avo/resources/api_tokens", params: { api_token: { revoked_at: "" } }
    end
    assert_redirected_to_avo_path "/avo/resources/api_tokens"
  end

  test "the api token index does not offer a New button" do
    sign_in
    ApiToken.generate!

    get "/avo/resources/api_tokens"

    assert_response :success
    assert_not_includes response.body, "/avo/resources/api_tokens/new"
  end

  # Deleting the last User from the admin would lock everyone out of the app
  # (the only other way to create one is the development-only seed).
  test "destroying a user through Avo is turned away instead of locking everyone out" do
    sign_in

    assert_no_difference -> { User.count } do
      delete "/avo/resources/users/#{@user.id}"
    end

    assert_redirected_to_avo_path "/avo/resources/users"
    assert User.exists?(@user.id)
  end

  test "the user pages do not offer a Delete button" do
    sign_in

    [ "/avo/resources/users", "/avo/resources/users/#{@user.id}", "/avo/resources/users/#{@user.id}/edit" ].each do |path|
      get path

      assert_response :success
      assert_no_match(/turbo-method=("|&quot;)delete/, response.body,
        "expected no delete control on #{path}")
    end
  end

  test "the post index can be filtered down to a single content type" do
    sign_in
    blog = Post.create!(title: "A blog post", content_type: :blog)
    resume = Post.create!(title: "A resume entry", content_type: :resume_entry)

    # Unfiltered, both posts are listed -- so the filtered assertion below is
    # not passing vacuously.
    get "/avo/resources/posts"
    assert_includes response.body, blog.title
    assert_includes response.body, resume.title

    get "/avo/resources/posts", params: {
      encoded_filters: Avo::Filters::BaseFilter.encode_filters(
        { "Avo::Filters::ContentType" => "blog" }
      )
    }

    assert_response :success
    assert_includes response.body, blog.title
    assert_not_includes response.body, resume.title
  end

  private
    # One persisted record per registered resource, for the Show coverage.
    def show_records
      post = Post.create!(title: "A shown post", content_type: :blog)
      post.tags << Tag.create!(name: "shown-tag")
      PostRelation.create!(post: post, related_post: Post.create!(title: "A related post", content_type: :blog))

      root = Page.create!(title: "A shown page")
      page = Page.create!(title: "A shown child page", slug: "child", parent: root)
      block = page.content_blocks.create!(block_type: :rich_text, position: 0)

      {
        "posts" => post,
        "tags" => post.tags.first,
        "site_settings" => SiteSetting.instance,
        "api_tokens" => ApiToken.generate!.first,
        "users" => @user,
        "pages" => page,
        "content_blocks" => block
      }
    end

    # The `src` of every lazily-loaded association turbo frame on a show page.
    def lazy_frame_sources(body)
      body.scan(/<turbo-frame\b[^>]*\bloading="lazy"[^>]*>/)
        .filter_map { |tag| tag[/\bsrc="([^"]+)"/, 1] }
        .map { |src| CGI.unescapeHTML(src) }
    end

    def assert_redirected_to_avo_path(path)
      assert_response :redirect
      assert_equal path, URI.parse(response.location).path
    end

    def sign_in
      post session_url, params: { email_address: @user.email_address, password: "password123" }
      assert_response :redirect
    end

    # Compare paths rather than using `assert_redirected_to new_session_path`:
    # after a request to an Avo controller the integration test's `url_options`
    # carry the engine's `script_name` ("/avo"), so the helper would expect
    # "/avo/session/new" instead of the app's real sign-in route.
    def assert_redirected_to_sign_in
      assert_response :redirect
      assert_equal Rails.application.routes.url_helpers.new_session_path,
        URI.parse(response.location).path
    end
end
