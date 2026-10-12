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

  NOWHERE = PublicSite::Branch::NOWHERE

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
    assert_equal [ @home.id, @guide.id ], branch.around(under).above.map(&:id)
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
    assert_equal [ @home.id, @guide.id ], branch.around(@install).above.map(&:id)
    assert_equal %w[Guide Write], titles(branch.around(@install).section)
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

  test "the pages above a page are nodes as published, the homepage first, and the homepage has none" do
    around = branch.around(@install)

    assert_equal [ @home.id, @guide.id, @start.id ], around.above.map(&:id)
    assert_equal [ [ "/", 0 ], [ "/guide", 1 ], [ "/guide/start", 2 ] ], around.above.map { |node| [ node.path, node.depth ] }
    assert around.above.all?(&:open?)
    assert_empty around.above.first.children, "the homepage's branch is not read for the pages above"
    assert_equal NOWHERE, branch.around(@home)
    assert_equal NOWHERE, branch.around(nil)

    assert Pages::Save.call(@guide, translations: { "en" => { title: "Guide CHANGED" } }).ok?
    assert_equal "Guide", branch.around(@install).above[1].title
    assert_equal "Guide CHANGED", branch(preview: true).around(@install).above[1].title
    assert_equal "/preview/guide", branch(preview: true).around(@install).above[1].path
  end

  test "the section around a page is its tree with the page marked, and the pages above are that tree's nodes" do
    around = branch.around(@install)

    assert_equal %w[Guide Start Install Write], titles(around.section)
    assert_equal [ "Install" ], around.section.reading_order.select(&:current?).map(&:title)
    assert_same around.section, around.above[1]
    assert_same around.section.children.first, around.above[2]
    assert_equal @guide.id, branch.around(@guide).section.id, "a page directly under the homepage is its own section"
    assert branch.around(@guide).section.current?
  end

  test "the section is found by its parent being the homepage; an unpublished one is no section, and the pages above are still named" do
    hidden = create_page(title: "Hidden", published: false)
    below = create_page(title: "Below", parent: hidden)
    draft = create_page(title: "Draft", parent: @guide, published: false)
    under = create_page(title: "Under", parent: draft)

    assert_nil branch.around(below).section
    assert_equal [ [ @home.id, 0 ] ], branch.around(below).above.map { |node| [ node.id, node.depth ] }
    assert_nil branch.around(hidden).section
    assert_equal @guide.id, branch.around(under).section.id
    assert_equal [ @home.id, @guide.id ], branch.around(under).above.map(&:id)
  end

  # I3: what a template is handed. A Page, even one rebuilt from its copy,
  # answers `.children` and `.content_blocks` from the rows.
  test "a node is a value: it answers what is documented and no way to a record or its rows" do
    assert Pages::Save.call(@start, translations: { "en" => { title: "Start", subtitle: "Where to begin" } }).ok?
    publish_changes(@start)
    assert Pages::Save.call(@start, translations: { "en" => { subtitle: "UNPUBLISHED" } }).ok?
    around = branch.around(@install)
    start = around.section.children.first

    assert_equal %i[id title subtitle slug path depth children current open], PublicSite::Branch::Node.members
    assert_equal [ @start.id, "Start", "Where to begin", "start", "/guide/start", 2 ], [ start.id, start.title, start.subtitle, start.slug, start.path, start.depth ]
    assert_nil around.section.subtitle
    assert_equal [ "", 0 ], [ around.above.first.slug, around.above.first.depth ]
    assert_equal [ 1, 2, 3, 2 ], around.section.reading_order.map(&:depth)
    assert_equal "UNPUBLISHED", branch(preview: true).around(@install).section.children.first.subtitle

    [ *around.above, *around.section.reading_order ].each do |node|
      assert_instance_of PublicSite::Branch::Node, node
      assert node.frozen?
      assert_kind_of Array, node.children
      assert node.children.frozen?, "a node is remembered for the render: what one partial adds to its children a later one would draw"
      %i[parent content_blocks attributes ancestors descendants siblings self_and_descendants page record owner
         read_attribute published_at reload save update].each do |name|
        assert_not_respond_to node, name
      end
      node.to_h.except(:children).each_value do |value|
        assert_includes [ String, Integer, NilClass, TrueClass, FalseClass ], value.class, "a node holds #{value.class}"
      end
    end
  end

  # A helper's argument is whatever a template hands it, and
  # `page_ancestors(@post || @page)` is what `language_links` is called with.
  # A post was taken for the PAGE with its number: another page's crumbs.
  test "what is neither a page nor a node is nowhere and no branch's top, and marks nothing as the shown page: a post with a page's id" do
    post = create_post(title: "A post")
    post.update_columns(id: @install.id) # version: none, changes: none (a test gives a post the id of a page, which two tables' sequences do by themselves)
    post = Post.find(@install.id)

    assert_equal NOWHERE, branch.around(post)
    assert_nil branch.under(post)
    assert_empty branch.under(@guide, current: post).reading_order.select { |node| node.current? || node.open? }
    assert_equal NOWHERE, branch.around(Struct.new(:id).new(@install.id))
    assert_empty capture_sql { branch.around(post); branch.under(post) }
  end

  # In the preview of a draft the tree holds published pages only, so the
  # shown page is not in it; the pages above it are, and they are open.
  test "every page above the shown one is open, also in the preview of a draft that the tree does not hold" do
    draft = create_page(title: "Draft", parent: @start, published: false)
    around = branch(preview: true).around(draft)

    assert_equal [ @home.id, @guide.id, @start.id ], around.above.map(&:id)
    assert around.above.all?(&:open?), around.above.map { |node| [ node.title, node.open? ] }.inspect
    assert_equal %w[Guide Start], around.section.reading_order.select(&:open?).map(&:title)
    assert_empty around.section.reading_order.select(&:current?)
  end

  # M7: the order of a sidebar is the order of every other list of the tree.
  test "pages are in the tree's own order, one without a position last: as the menu's and CS Studio's tree" do
    last = create_page(title: "Last", parent: @guide)
    @start.update_columns(position: nil) # version: none (a test takes a position away, as only a half-written row has none)
    PublicSite::Paths.rebuild!

    in_branch = branch.under(@guide).children.map(&:id)

    assert_equal [ @write.id, last.id, @start.id ], in_branch
    assert_equal @guide.children.kept.published.pluck(:id), in_branch, "the public tree's own order (closure_tree's)"
    assert_equal AccessControl.preload_branches(Page.all.to_a).select { |page| page.parent_id == @guide.id }.map(&:id), in_branch, "CS Studio's tree"
  end

  test "under takes a node for its top and for the shown page" do
    tree = branch.under(@guide, current: @install)
    again = branch.under(tree.children.first, current: tree.children.first.children.first)

    assert_equal %w[Start Install], titles(again)
    assert_equal 2, again.depth
    assert again.children.first.current?
    assert_nil branch.under(nil)
  end

  test "a branch costs four statements at 4 pages and at 30, the homepage's three, and what is around a page four with none per page above" do
    branch.under(@guide, current: @install) # the settings row and the schema are read once, here
    small = capture_sql { branch.under(@guide, current: @install) }
    around_small = capture_sql { branch.around(@install) }

    26.times { |index| create_page(title: "Leaf #{index}", parent: index.even? ? @write : @start) }
    deep = create_page(title: "Deep", parent: create_page(title: "Deeper", parent: @install))
    large = capture_sql { @tree = branch.under(@guide, current: @install) }
    around_large = capture_sql { @around = branch.around(deep) }
    whole = capture_sql { @site = branch.under(@home) }

    assert_equal 32, @tree.reading_order.size
    assert_equal 5, @around.above.size
    assert_equal 33, @site.reading_order.size
    assert_equal 4, small.size, small.join("\n")
    assert_equal 4, large.size, large.join("\n")
    assert_equal 4, around_small.size, around_small.join("\n")
    assert_equal 4, around_large.size, around_large.join("\n")
    assert_equal 3, whole.size, whole.join("\n")
    assert_equal 1, capture_sql { branch.around(@home) }.size
  end
end
