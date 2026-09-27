require "test_helper"

class Admin::ShellTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "the admin lives under ADMIN_PATH and requires sign-in" do
    assert_equal "cs-studio", ContentSpiel::ADMIN_PATH
    get "/cs-studio"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "signing in lands in CS Studio with the modules column" do
    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio"
    follow_redirect!
    assert_select "nav[aria-label='Modules'] a", text: "Pages"
    assert_select "nav[aria-label='Modules'] a", text: "Posts"
    assert_select "nav[aria-label='Modules'] a", text: "Tags"
    assert_select "nav[aria-label='Modules'] a[href='/avo/resources/users']", text: /Users/
  end

  test "the old public sign-in routes are gone" do
    get "/session/new"
    assert_response :not_found
  end

  test "a root child page can't take the admin path as its slug" do
    page = Page.new(parent: root_page, title: "Studio", slug: "cs-studio")
    assert_not page.valid?
    assert page.errors.full_messages.any? { |message| message.include?("reserved for the admin") }
  end

  test "an unknown locale param falls back to the default" do
    sign_in_as(users(:one))
    get "/cs-studio", params: { locale: "xx" }
    assert_response :success
    assert_select "[data-admin-locale='#{Locales.default}']"
  end

  # Fix (final-fixes round, finding 4): a GET is the one case worth
  # remembering at all -- signing back in should land exactly where the
  # editor was.
  test "an unauthenticated GET remembers the URL to return to after signing in" do
    page = create_page(title: "About")

    get "/cs-studio/pages/#{page.id}"
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio/pages/#{page.id}"
  end

  # Fix (final-fixes round, finding 4): an expired session's autosave PATCH
  # must never be remembered as the URL to return to -- unlike a page's own
  # `/cs-studio/pages/:id` (which happens to answer both GET and PATCH), a
  # block card's own `/cs-studio/pages/:id/content_blocks/:id` or the tree's
  # `/cs-studio/tree` have no GET route at all, so replaying that same URL
  # after signing back in would 404/routing-error instead of landing
  # anywhere useful. `request_authentication` falls back to the referer (the
  # page the form itself lives on) for any non-GET request instead.
  test "an unauthenticated non-GET request never remembers its own URL as the return_to" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    patch "/cs-studio/pages/#{page.id}/content_blocks/#{block.id}",
      params: { block: { body: "<p>x</p>" } },
      headers: { "HTTP_REFERER" => "/cs-studio/pages/#{page.id}" }
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio/pages/#{page.id}"
  end

  test "an unauthenticated non-GET request with no referer falls back to CS Studio's own root, not a 404" do
    page = create_page(title: "About")

    patch "/cs-studio/pages/#{page.id}", params: { page: { title: "x" } }
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio"
  end
end
