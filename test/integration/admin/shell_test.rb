require "test_helper"
require "open3"

class Admin::ShellTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "the admin lives under ADMIN_PATH and requires sign-in" do
    assert_equal "cs-studio", ContentSpiel::ADMIN_PATH
    get "/cs-studio"
    assert_redirected_to "/cs-studio/sign-in"
  end

  # Fix (final-fixes round, finding 8): the reserved list itself, checked
  # directly (no subprocess needed) -- every static first segment another
  # route in this app already claims, plus every locale `SUPPORTED_LOCALES`
  # could ever have enabled (not just `Locales.enabled`, a runtime setting
  # this boot-time constant can't read).
  test "the reserved-paths denylist covers every already-claimed first segment" do
    assert_equal(
      (%w[preview setup mcp up avo rails lookbook assets cable sitemap.xml] + SUPPORTED_LOCALES.keys).sort,
      ContentSpiel::RESERVED_PATHS.sort
    )
  end

  # Fix (final-fixes round, finding 8): the actual boot-time refusal, proven
  # by really booting -- `ContentSpiel::ADMIN_PATH` is a constant, set once
  # when this process itself booted, so there's no way to re-run its own
  # `tap` block against a bad value from inside this already-running test
  # process. A subprocess is what actually re-triggers it: one static
  # reserved word (`avo`) and one locale code (`de`), enough to prove both
  # halves of the denylist actually reach the raise, not every one of
  # `RESERVED_PATHS`' several dozen entries -- the list itself is already
  # covered exhaustively, without a subprocess, just above.
  test "booting with a reserved ADMIN_PATH actually fails" do
    %w[avo de].each do |reserved|
      output, status = Open3.capture2e({ "ADMIN_PATH" => reserved, "RAILS_ENV" => "test" }, "bin/rails", "runner", "1")
      assert_not status.success?, "expected ADMIN_PATH=#{reserved} to fail boot"
      assert_includes output, "already reserved"
    end
  end

  test "signing in lands in CS Studio with the modules column" do
    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio"
    follow_redirect!
    assert_select "nav[aria-label='Modules'] a", text: "Pages"
    assert_select "nav[aria-label='Modules'] a", text: "Posts"
    assert_select "nav[aria-label='Modules'] a", text: "Tags"

    # Settings and Users are CS Studio's own screens now (Task 8), not
    # "(old admin)" links out to Avo -- the modules column links straight
    # to them the same way it already does for Pages/Posts/Tags.
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/settings']", text: "Settings"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/users']", text: "Users"
    assert_select "nav[aria-label='Modules'] a[href='/avo/resources/users']", count: 0
    assert_select "nav[aria-label='Modules'] a[href='/avo/resources/site_settings']", count: 0

    # The last old-admin screens are CS Studio modules now (Task 9): the
    # "(old admin)" group is gone, and nothing in the shell links to /avo.
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/api_tokens']", text: "AI assistant"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/system_status']", text: "System status"
    assert_select "a[href^='/avo']", count: 0
    assert_not_includes response.body, "(old admin)"
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
