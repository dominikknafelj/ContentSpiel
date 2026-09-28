require "test_helper"

# SiteSetting#default_locale is a runtime setting (editable in CS Studio, no
# deploy required) that decides which of the site's locales is served with no
# prefix at all. Every other test in this suite exercises the *default*
# default_locale ("en") -- this file is what actually proves the setting is
# live, not just stored: changing it has to change routing, redirects, and
# the sitemap on the very next request.
class DefaultLocaleTest < ActionDispatch::IntegrationTest
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: @root,
      published_at: Time.current)
    Mobility.with_locale(:de) { @about.update!(title: "Über uns", slug: "ueber-uns") }

    SiteSetting.instance.update!(default_locale: "de")
  end

  test "the unprefixed root and paths serve the new default locale" do
    get "/"
    assert_response :success
    assert_includes response.body, "Home"

    get "/ueber-uns"
    assert_response :success
    assert_includes response.body, "Über uns"
  end

  test "the new default locale's own prefix redirects to the unprefixed URL" do
    get "/de/ueber-uns"

    assert_redirected_to "/ueber-uns"
  end

  # The locale that used to be default is just another configured locale now
  # -- reachable at its own prefix, rendered directly, no redirect.
  test "the locale that stopped being default renders directly at its own prefix" do
    get "/en/about"

    assert_response :success
    assert_includes response.body, "About"
  end

  test "page_url_path omits the prefix for the new default and adds one for the old" do
    # `page_url_path` now delegates to `PagesController#public_urls` (spec
    # §6.2), which needs a real request to read its host from -- a bare
    # `ApplicationController.new.view_context` (as this test used before)
    # never has one, so a live dispatch stands in for it.
    get "/"
    view = @controller.view_context

    assert_equal "/ueber-uns", view.page_url_path(@about, :de)
    assert_equal "/en/about", view.page_url_path(@about, :en)
  end

  # Task 8c / code-structure review finding #2: before this fix, a page
  # titled only in the site's default locale left every other locale's slug
  # blank, and a blank non-root slug collapses onto the parent's path
  # (page.rb's own comment on `validates :slug` walks through the
  # two-pages-one-URL collision that produces). Here the default locale is
  # German and the new child is titled only in German, so English and
  # Spanish are the locales that would have collapsed onto @root's path --
  # "/en" and "/es" -- instead of getting a path of their own.
  test "a page titled only in the default locale still gets its own path in every other locale" do
    kontakt = Mobility.with_locale(:de) do
      Page.create!(page_type: :standard, title: "Kontakt", parent: @root, published_at: Time.current)
    end

    # The slug (this task's fix) is what's under test -- reading the title
    # back through Mobility's own fixed-:en fallback is a separate, explicitly
    # out-of-scope concern (task brief), so this doesn't assert on rendered
    # German copy showing up on an English page.
    assert_not_equal @root.full_path(:en), kontakt.full_path(:en)
    assert_not_equal @root.full_path(:es), kontakt.full_path(:es)

    get "/"
    assert_equal "/en/kontakt", @controller.view_context.page_url_path(kontakt, :en)

    get "/en/kontakt"
    assert_response :success

    # And Home itself is unharmed: the collapse this guards against would
    # have made Home and Kontakt both answer to "/en".
    get "/en"
    assert_response :success
    assert_includes response.body, "Home"

    get "/"
    assert_response :success
    assert_includes response.body, "Home"
  end

  test "the sitemap swaps which locale is unprefixed" do
    require "sitemap_generator"
    require "tmpdir"

    paths = Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir,
        compress: false, verbose: false)
      xml = Nokogiri::XML(File.read(File.join(dir, "sitemap.xml")))
      xml.remove_namespaces!.css("url > loc").map { |loc| URI.parse(loc.text).path }
    end

    assert_includes paths, "/ueber-uns"
    assert_includes paths, "/en/about"
    assert_not_includes paths, "/about"
    assert_not_includes paths, "/de/ueber-uns"
  end
end
