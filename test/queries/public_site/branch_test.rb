require "test_helper"

# A branch of the page tree as a theme's template is given it (theming spec
# §7): kept and published pages only, titles as published, addresses as
# stored, in a number of statements that does not grow with the branch.
class PublicSite::BranchTest < ActiveSupport::TestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @home = root_page
    @guide = create_page(title: "Guide")
    @start = create_page(title: "Start", parent: @guide)
    @install = create_page(title: "Install", parent: @start)
    @write = create_page(title: "Write", parent: @guide)
  end

  def branch(locale: "en", preview: false) = PublicSite::Branch.new(urls: PublicSite::Urls.new(preview: preview), locale: locale)

  def titles(node) = node.reading_order.map(&:title)

  test "the branch is nested as the tree is, in the tree's order, with addresses" do
    tree = branch.under(@guide)

    assert_equal "Guide", tree.title
    assert_equal "/guide", tree.path
    assert_equal %w[Start Write], tree.children.map(&:title)
    assert_equal [ "Install" ], tree.children.first.children.map(&:title)
    assert_equal "/guide/start/install", tree.children.first.children.first.path
    assert_equal %w[Guide Start Install Write], titles(tree)
    assert tree.children.last.leaf?
    assert_not tree.leaf?
  end

  test "the shown page is current, and every page it is somewhere below is open" do
    tree = branch.under(@guide, current: @install)
    by_title = tree.reading_order.index_by(&:title)

    assert by_title["Install"].current?
    assert_equal [ "Install" ], tree.reading_order.select(&:current?).map(&:title)
    assert by_title["Guide"].open?
    assert by_title["Start"].open?
    assert_not by_title["Install"].open?, "the shown page is current, not open"
    assert_not by_title["Write"].open?
    assert_empty branch.under(@guide).reading_order.select { |node| node.current? || node.open? }, "with no page shown nothing is marked"
  end

  test "an unpublished page leaves with its branch" do
    draft = create_page(title: "Draft", parent: @guide, published: false)
    create_page(title: "Under the draft", parent: draft)

    assert_equal %w[Guide Start Install Write], titles(branch.under(@guide))
    assert_nil branch.under(draft)
  end

  test "a scheduled page joins the branch by the clock, and a scheduled change of a title shows by it too" do
    later = create_page(title: "Later", parent: @guide, published: false)
    assert Pages::Save.call(later, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(@write, translations: { "en" => { title: "Write CHANGED" } }).ok?
    publish_changes(@write, at: 2.days.from_now)

    assert_equal %w[Guide Start Install Write], titles(branch.under(@guide))
    assert_nil branch.under(later)

    travel_to 3.days.from_now do
      assert_equal [ "Guide", "Start", "Install", "Write CHANGED", "Later" ], titles(branch.under(@guide))
      assert_equal "Later", branch.under(later).title
    end
  end

  test "a published page under an unpublished one is in no branch, and above a page only published pages are named" do
    draft = create_page(title: "Draft", parent: @guide, published: false)
    under = create_page(title: "Under the draft", parent: draft)

    assert_not_includes titles(branch.under(@guide)), "Under the draft"
    assert_equal [ @home.id, @guide.id ], branch.above(under).map(&:id)
  end

  test "a trashed page is absent, and a branch whose top is trashed is nothing" do
    @start.update!(trashed_at: Time.current)

    assert_equal %w[Guide Write], titles(branch.under(@guide))
    assert_nil branch.under(@start.reload)
  end

  # A page in the trash has no address either, which alone would keep it out
  # of a branch; these rows are written around the callbacks, so the address
  # is still stored and only the narrowing on the rows is asked.
  test "a page in the trash is in no branch and above no page, although its address is still stored" do
    @start.update_columns(trashed_at: Time.current) # version: none (a test puts a row in the trash around the callbacks, so its address stays)
    assert PublicPath.current.exists?(record_type: "Page", record_id: @start.id)

    assert_equal %w[Guide Write], titles(branch.under(@guide))
    assert_nil branch.under(@start)
    assert_equal [ @home.id, @guide.id ], branch.above(@install).map(&:id)
  end

  test "titles are the published ones, and in a preview the rows'" do
    assert Pages::Save.call(@start, translations: { "en" => { title: "Start CHANGED" } }).ok?

    assert_equal %w[Guide Start Install Write], titles(branch.under(@guide)), "an unpublished title reached the tree"
    assert_equal [ "Guide", "Start CHANGED", "Install", "Write" ], titles(branch(preview: true).under(@guide))
    assert_equal "/preview/guide/start", branch(preview: true).under(@guide).children.first.path

    publish_changes(@start)
    assert_equal [ "Guide", "Start CHANGED", "Install", "Write" ], titles(branch.under(@guide))
  end

  test "another language has its own addresses, and a title falls back as everywhere" do
    tree = branch(locale: "de").under(@guide)

    assert_equal "/de/guide", tree.path
    assert_equal %w[Guide Start Install Write], titles(tree)
  end

  test "a page with no address in this language is left out with its branch" do
    PublicPath.where(record_type: "Page", record_id: @start.id, locale: "de").delete_all # version: none (a test takes one address away to see the tree without it)

    assert_equal %w[Guide Write], titles(branch(locale: "de").under(@guide))
    assert_equal %w[Guide Start Install Write], titles(branch.under(@guide)), "the other language keeps the page"
  end

  test "the pages above a page are the published ones, the homepage first, and the homepage has none" do
    assert_equal [ @home.id, @guide.id, @start.id ], branch.above(@install).map(&:id)
    assert_empty branch.above(@home)

    assert Pages::Save.call(@guide, translations: { "en" => { title: "Guide CHANGED" } }).ok?
    assert_equal "Guide", Locales.read(branch.above(@install)[1], :title, locale: "en")
    assert_equal "Guide CHANGED", Locales.read(branch(preview: true).above(@install)[1], :title, locale: "en")
  end

  test "a branch costs three statements at 4 pages and at 30" do
    branch.under(@guide, current: @install) # the settings row and the schema are read once, here
    small = capture_sql { branch.under(@guide, current: @install) }

    26.times { |index| create_page(title: "Leaf #{index}", parent: index.even? ? @write : @start) }
    large = capture_sql { @tree = branch.under(@guide, current: @install) }

    assert_equal 30, @tree.reading_order.size
    assert_equal 3, small.size, small.join("\n")
    assert_equal 3, large.size, large.join("\n")
  end
end
