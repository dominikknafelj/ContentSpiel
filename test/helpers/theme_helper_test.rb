require "test_helper"

class ThemeHelperTest < ActionView::TestCase
  # `language_links` calls `public_urls`, defined on PagesController (not a
  # helper module) via `helper_method` -- ActionView::TestCase's view context
  # never gets a controller's helper_method delegates, only app/helpers
  # modules, so this test stands in with its own instance, the same
  # `PublicSite::Urls.new` PagesController's own definition builds, just
  # without a request to read a host from (nothing here asserts on an
  # absolute URL).
  include PagesHelper

  def public_urls
    @public_urls ||= PublicSite::Urls.new
  end

  # Fix round 1 (review of 221fba9): `language_links` regressed to English
  # names ("German") when it switched from `SetupHelper::LANGUAGE_NAMES`
  # (native names) to `Locales.name(code)` (English by default). The
  # `<details>` switcher markup (app/views/layouts/public/_language_switcher
  # .html.erb) only renders `link.name` once there are more than three
  # enabled locales -- this app is pinned to exactly three
  # (config/application.rb) -- so an integration test can't reach this text;
  # a direct helper test is the only way to pin it.
  test "language_links names each locale natively, not in English" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    page = Page.create!(parent: root, page_type: :standard, title_en: "About", title_de: "Über",
      published_at: Time.current)

    links = language_links(page)

    assert_equal "English", links.find { |link| link.code == "en" }.name
    assert_equal "Deutsch", links.find { |link| link.code == "de" }.name, "not the English name 'German'"
    assert_equal "Español", links.find { |link| link.code == "es" }.name, "not the English name 'Spanish'"
  end

  # --- the page tree and the article, for a theme (theming spec §7) ----------

  def tree_node(title, children: [], current: false)
    PublicSite::Branch::Node.new(id: title.hash, title: title, path: "/#{title.downcase}", children: children, current: current, open: false)
  end

  test "page_tree, page_section and page_ancestors read a branch once per render, as published" do
    home = root_page
    guide = create_page(title: "Guide")
    start = create_page(title: "Start", parent: guide)

    assert_nil page_section(home)
    assert_equal guide.id, page_section(guide).id
    assert_equal guide.id, page_section(start).id
    assert_equal [ home.id, guide.id ], page_ancestors(start).map(&:id)

    tree = page_tree(guide, current: start)
    assert_equal %w[Guide Start], pages_in_reading_order(tree).map(&:title)
    assert tree.children.first.current?
    assert_same tree, page_tree(guide, current: start), "a second call in the same render reads nothing"
    assert_empty capture_sql { page_tree(guide, current: start); page_ancestors(start); page_section(start) }
    assert_empty pages_in_reading_order(nil)
  end

  test "navigation_pages is read once per render" do
    create_page(title: "About")

    first = navigation_pages

    assert_equal [ "About" ], first.map { |page| translated(page, :title) }
    assert_empty capture_sql { navigation_pages }
    assert_same first, navigation_pages
  end

  test "neighbouring_pages are the pages before and after the shown one, nil at either end" do
    tree = ->(current) do
      tree_node("Guide", current: current == "Guide", children: [
        tree_node("Start", current: current == "Start", children: [ tree_node("Install", current: current == "Install") ]),
        tree_node("Write", current: current == "Write")
      ])
    end

    assert_equal [ nil, "Start" ], neighbouring_pages(tree.("Guide")).map { |found| found&.title }
    assert_equal %w[Start Write], neighbouring_pages(tree.("Install")).map { |found| found&.title }
    assert_equal [ "Install", nil ], neighbouring_pages(tree.("Write")).map { |found| found&.title }
    assert_equal [ nil, nil ], neighbouring_pages(tree.("Nowhere"))
    assert_equal [ nil, nil ], neighbouring_pages(nil)
  end

  test "neighbouring_pages walks past the pages skip names, and never skips the shown one" do
    tree = tree_node("Guide", children: [
      tree_node("Start", children: [ tree_node("Install", current: true) ]),
      tree_node("Write", children: [ tree_node("Drafts") ])
    ])
    groups = ->(found) { !found.leaf? }

    assert_equal [ nil, "Drafts" ], neighbouring_pages(tree, skip: groups).map { |found| found&.title }

    shown_group = tree_node("Guide", children: [ tree_node("Start", current: true, children: [ tree_node("Install") ]), tree_node("Write") ])
    assert_equal [ nil, "Install" ], neighbouring_pages(shown_group, skip: groups).map { |found| found&.title }
  end

  test "with_heading_ids gives each heading of the levels asked for an id made from its words, and lists them" do
    html, headings = with_heading_ids("<h2>Getting started</h2><p>Text</p><h3>Next steps</h3><h4>Deeper</h4>".html_safe)

    assert_equal [ [ "getting-started", "Getting started", 2 ], [ "next-steps", "Next steps", 3 ] ], headings.map { |heading| [ heading.id, heading.text, heading.level ] }
    assert_includes html, %(<h2 id="getting-started">Getting started</h2>)
    assert_includes html, %(<h3 id="next-steps">Next steps</h3>)
    assert_includes html, "<h4>Deeper</h4>"
    assert html.html_safe?

    _, deeper = with_heading_ids("<h2>A</h2><h4>Deeper</h4>".html_safe, levels: 2..4)
    assert_equal %w[a deeper], deeper.map(&:id)
  end

  test "two headings alike, an empty one, one in another script and one with markup each get an id of their own" do
    source = "<h2>Setup</h2><h2>Setup</h2><h2></h2><h2>日本語</h2><h2>Use <code>bin/rails</code> &amp; more</h2><h2>Setup</h2>"
    html, headings = with_heading_ids(source.html_safe)

    assert_equal %w[setup setup-2 section 日本語 use-bin-rails-more setup-3], headings.map(&:id)
    assert_equal headings.map(&:id), headings.map(&:id).uniq
    assert_equal "Use bin/rails & more", headings[4].text
    assert_includes html, %(<h2 id="use-bin-rails-more">Use <code>bin/rails</code> &amp; more</h2>)
  end

  test "with_heading_ids keeps an id a heading already has and never gives it to another" do
    _, headings = with_heading_ids(%(<h2 id="setup">Other words</h2><h2>Setup</h2><p id="setup-2">x</p><h2>Setup</h2>).html_safe)

    assert_equal %w[setup setup-3 setup-4], headings.map(&:id)
  end

  test "a string that is not markup comes back escaped: with_heading_ids is no way to print a title as markup" do
    html, headings = with_heading_ids("<h2>Typed</h2><script>x</script>")

    assert_equal "&lt;h2&gt;Typed&lt;/h2&gt;&lt;script&gt;x&lt;/script&gt;", html
    assert html.html_safe?
    assert_empty headings
  end

  test "with_heading_ids of nothing is nothing" do
    html, headings = with_heading_ids(nil)

    assert_equal "", html
    assert_empty headings
  end

  # The site has 38 languages: a heading that `parameterize` would empty
  # keeps its own letters, so its id follows its words as a Latin one's does
  # and is not a number that moves when a heading is added above it.
  test "a heading in another script keeps its letters: its id is its words, not its place on the page" do
    source = "<h2>Εγκατάσταση και ρύθμιση</h2><h2>التثبيت</h2><h2>インストール 手順</h2><h2>Установка Rails 8</h2><h2>Über uns</h2><h2>Hướng dẫn cài đặt</h2><h2>हिन्दी</h2><h2>🎉 ?!</h2><h2>التثبيت</h2>"
    html, headings = with_heading_ids(source.html_safe)

    assert_equal [ "εγκατάσταση-και-ρύθμιση", "التثبيت", "インストール-手順", "установка-rails-8", "uber-uns", "huong-dan-cai-dat", "हिन्दी", "section", "التثبيت-2" ], headings.map(&:id)
    assert_includes html, %(<h2 id="εγκατάσταση-και-ρύθμιση">)
    headings.each { |heading| assert_match(/\A[\p{L}\p{M}\p{N}_-]+\z/, heading.id) }
  end

  test "nothing of a heading's words but letters, marks and digits reaches its id" do
    source = %(<h2>a"b'c&lt;d&gt;e&amp;f g\th=i/j#k%l</h2><h2>&lt;script&gt;alert(1)&lt;/script&gt;</h2><h2>   </h2>)
    html, headings = with_heading_ids(source.html_safe)

    assert_equal %w[a-b-c-d-e-f-g-h-i-j-k-l script-alert-1-script section], headings.map(&:id)
    assert_equal 3, Nokogiri::HTML5.fragment(html).css("h2[id]").size
    assert_empty Nokogiri::HTML5.fragment(html).css("script")
  end

  test "the same words give the same id on every call, and a text with no heading of the levels asked comes back as it was" do
    source = "<h2>Setup</h2><p>One</p>".html_safe
    assert_equal with_heading_ids(source).last, with_heading_ids(source).last

    plain = %(<p class="a">One<br>two</p><h4>Deeper</h4>).html_safe
    html, headings = with_heading_ids(plain)
    assert_same plain, html
    assert_empty headings
  end

  test "page_section is the page directly under the homepage, whatever is unpublished above the page, and nil when that page is not shown" do
    home = root_page
    guide = create_page(title: "Guide")
    draft = create_page(title: "Draft", parent: guide, published: false)
    under = create_page(title: "Under", parent: draft)
    hidden = create_page(title: "Hidden", published: false)
    below = create_page(title: "Below", parent: hidden)

    assert_equal guide.id, page_section(under).id, "the unpublished page between them is not the section"
    assert_nil page_section(below), "its branch under the homepage is not published"
    assert_nil page_section(hidden)
    assert_nil page_section(home)
  end
end
