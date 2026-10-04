require "test_helper"

# "Create starter pages" on the Pages index (design spec §6.1): reuses
# `StarterContent.create_pages_and_posts!` as-is, offered only while the
# starter sections don't exist yet, and refreshes the whole shell (the
# tree lives outside the content frame) with a `_top` redirect.
class Admin::StarterContentsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    root_page
  end

  test "the Pages index offers the action while the starter pages are missing" do
    get "/cs-studio/pages/#{root_page.id}"

    assert_select "form[action='/cs-studio/starter_contents'][data-turbo-frame='_top']", minimum: 1
    assert_select "button", text: "Create starter pages"
  end

  test "starter pages are offered only while Home is the only kept page" do
    get "/cs-studio/pages/#{root_page.id}"
    assert_select "button", text: "Create starter pages"

    page = create_page(title: "About")
    get "/cs-studio/pages/#{root_page.id}"
    assert_select "button", text: "Create starter pages", count: 0

    # A trashed page isn't a page the site has built: the offer is back.
    page.update!(trashed_at: Time.current)
    get "/cs-studio/pages/#{root_page.id}"
    assert_select "button", text: "Create starter pages"
  end

  test "creating adds a page per section and redirects to the Pages index" do
    sections = StarterContent.sections.size
    assert sections.positive?

    assert_difference -> { Page.count }, sections do
      post "/cs-studio/starter_contents"
    end

    assert_redirected_to "/cs-studio/pages"
    follow_redirect! # /pages opens Home, keeping the flash
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
    follow_redirect!
    assert_select "[role=status]", text: "Starter pages already exist"
  end

  # Fix round 1 (m3): the check and the creation run under the site
  # settings row lock, so a second request re-checks after the first
  # commits -- and anything that still fails rolls back into an alert,
  # never a 500 or a half-built section.
  test "a creation failure rolls back and answers with an alert, not a 500" do
    home = root_page
    with_singleton_override(StarterContent, :create_pages_and_posts!, ->(**) {
      Pages::Save.call(attributes: { parent: home, published: true }, translations: { "en" => { title: "Half built" } })
      raise StarterContent::Error, "StarterContent: Slug has already been taken"
    }) do
      assert_no_difference [ "Page.count", "Post.count" ] do
        post "/cs-studio/starter_contents"
      end
    end

    assert_redirected_to "/cs-studio/pages"
    follow_redirect!
    follow_redirect!
    assert_select "[role=alert]", text: /couldn.t be added/
  end

  test "a request from a stale tab re-checks and finds the sections another tab created" do
    get "/cs-studio/pages/#{root_page.id}"
    assert_select "button", text: "Create starter pages" # this tab still offers it

    StarterContent.create_pages_and_posts!(locale: "en") # another tab finished first

    assert_no_difference [ "Page.count", "Post.count" ] do
      post "/cs-studio/starter_contents"
    end
    follow_redirect!
    follow_redirect!
    assert_select "[role=status]", text: "Starter pages already exist"
  end
end
