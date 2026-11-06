require "test_helper"

# A page's subpages list on the public site is navigation: a mono label names
# it ("In this section", read in the visitor's language through
# ThemeHelper#site_string), its links are set as the header's menu is, and it
# is drawn only where there is something to list and the page is not a post's
# own view.
class PublicSubpagesTest < ActionDispatch::IntegrationTest
  # The German test stores a word into the shared backend; reloading puts the
  # files' translations back for every test that follows.
  teardown { I18n.reload! }

  setup { root_page }

  def path_of(record, locale = "en") = PublicSite::Urls.new.path_for(record, locale)

  test "a page with published subpages names the list In this section, in the label voice, and its links are the menu's: dim, ink on hover, no underline, one per line" do
    parent = create_page(title: "Guides")
    first = create_page(title: "First steps", parent: parent)
    second = create_page(title: "Going further", parent: parent)

    get path_of(parent)

    assert_select "nav.page-children[aria-labelledby]" do |navs|
      label_id = navs.first["aria-labelledby"]
      assert_select "p#{'#'}#{label_id}.text-label", text: "In this section"
    end
    assert_select "nav.page-children li", count: 2
    assert_select "nav.page-children li a", count: 2 do |links|
      assert_equal [ "First steps", "Going further" ], links.map { |a| a.text.strip }
      assert_equal [ path_of(first), path_of(second) ], links.map { |a| a["href"] }
      links.each do |a|
        classes = a["class"].split
        assert_includes classes, "text-dim"
        assert_includes classes, "hover:text-ink"
        assert_not_includes classes, "underline"
      end
    end
  end

  test "in a language without a public locale file the label is English, and with one it is that language's" do
    parent = create_page(title: "Guides")
    create_page(title: "First steps", parent: parent)

    get path_of(parent, "de")
    assert_response :success
    assert_select "nav.page-children p", text: "In this section"

    I18n.backend.store_translations(:de, public: { site: { in_this_section: "In diesem Bereich" } })
    get path_of(parent, "de")
    assert_select "nav.page-children p", text: "In diesem Bereich"
    assert_select "nav.page-children p", text: "In this section", count: 0
  end

  test "a post's own page draws no subpages list, though its listing page has subpages" do
    listing = create_page(title: "Blog")
    ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    create_page(title: "Archive", parent: listing)
    publish_changes(listing)
    post = create_post(title: "Hello")

    get path_of(listing)
    assert_select "nav.page-children", count: 1

    get path_of(post)
    assert_response :success
    assert_select "article h1", text: "Hello"
    assert_select "nav.page-children", count: 0
    assert_not_includes response.body, "In this section"
  end

  test "a page whose subpages are all drafts or in the trash draws no list, no label and no rule" do
    parent = create_page(title: "Guides")
    create_page(title: "Draft one", parent: parent, published: false)
    trashed = create_page(title: "Gone", parent: parent)
    assert Trash::Move.call(trashed).ok?

    get path_of(parent)

    assert_response :success
    assert_select "nav.page-children", count: 0
    assert_not_includes response.body, "In this section"
  end

  # One statement for the list's addresses (`PublicSite::Urls#prefetch`), not
  # one per subpage: the number of statements that read `public_paths` is the
  # same for three subpages and for thirty.
  test "the subpages' addresses are read in one statement at 3 and at 30 subpages" do
    reads = [ 3, 30 ].map do |count|
      parent = create_page(title: "Guides #{count}")
      children = Array.new(count) { |index| create_page(title: "Step #{index}", parent: parent) }
      get path_of(parent)
      sql = capture_sql { get path_of(parent) }

      assert_response :success
      assert_select "nav.page-children li a", count: count do |links|
        assert_equal children.map { |child| path_of(child) }, links.map { |a| a["href"] }
      end
      sql.grep(/public_paths/i)
    end

    assert_equal reads.first.size, reads.last.size, "a subpage costs a statement of its own:\n#{reads.last.join("\n")}"
  end
end
