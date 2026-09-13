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

    %w[posts tags site_settings api_tokens].each do |resource|
      get "/avo/resources/#{resource}"

      assert_response :success, "expected /avo/resources/#{resource} to render"
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
