require "test_helper"

# "Create starter pages" on the Pages home (design spec §6.1): reuses
# `StarterContent.create_pages_and_posts!` as-is, offered only while the
# starter sections don't exist yet, and refreshes the whole shell (the
# tree lives outside the content frame) with a `_top` redirect.
class Admin::StarterContentsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    root_page
  end

  test "the Pages home offers the action while the starter pages are missing" do
    get "/cs-studio"

    assert_select "form[action='/cs-studio/starter_contents'][data-turbo-frame='_top']", minimum: 1
    assert_select "button", text: "Create starter pages"
  end

  test "creating adds a page per section and redirects to the Pages home" do
    sections = StarterContent.sections.size
    assert sections.positive?

    assert_difference -> { Page.count }, sections do
      post "/cs-studio/starter_contents"
    end

    assert_redirected_to "/cs-studio"
    follow_redirect!
    assert_select "#tree", text: /Blog/
    assert_select "[role=status]", text: "Starter pages created"
    assert_select "button", text: "Create starter pages", count: 0
  end

  test "running it again is idempotent and explains why nothing happened" do
    post "/cs-studio/starter_contents"

    assert_no_difference [ "Page.count", "Post.count" ] do
      post "/cs-studio/starter_contents"
    end

    follow_redirect!
    assert_select "[role=status]", text: "Starter pages already exist"
  end
end
