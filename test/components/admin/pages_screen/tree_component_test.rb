require "test_helper"

# The page tree's cost profile with translation markers on (final fix wave,
# I1/T4): the tree is re-rendered after every page-settings autosave, so it
# must cost the same handful of queries however many pages (and blocks) it
# shows; its markers are one read of the stored `translation_states`.
class Admin::PagesScreen::TreeComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def add_pages(count, prefix)
    Array.new(count) do |index|
      page = create_page(title: "#{prefix} #{index}", translations: { "de" => { title: "#{prefix} #{index} (de)" } })
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
      assert result.ok?, result.errors.to_sentence
      page
    end
  end

  test "the tree's list script is told how many ids one request may ask about" do
    render_tree

    assert_selector "turbo-frame#tree[data-admin--presence--list-chunk-value='#{Presence::HERE_IDS}']"
  end

  def render_tree = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, locale: "en"))

  # Every statement sent, cached or not (the same counting the tree's
  # access-control query test uses): a per-row query shows up either way.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  test "the tree with translation markers costs the same queries for 3 pages as for 30" do
    with_locales(%w[en de es], default: "en") do
      add_pages(3, "Small")
      render_tree # warm up whatever a first render loads once
      small = count_queries { render_tree }

      add_pages(27, "Large")
      large = count_queries { render_tree }

      assert_selector "li.admin-tree-node", minimum: 31
      assert_equal small, large, "the tree ran a query per page"
    end
  end

  test "the tree with open notes on its pages costs the same queries for 3 pages as for 30, and draws a pill on each" do
    add_notes = ->(pages) { as(users(:two)) { pages.each { |page| Notes::Start.call(page, body: "A note") } } }

    small_pages = add_pages(3, "Small")
    add_notes.(small_pages)
    render_tree # warm up whatever a first render loads once
    small = count_queries { render_tree }

    large_pages = add_pages(27, "Large")
    add_notes.(large_pages)
    large = count_queries { render_tree }

    assert_selector "span[data-notes-marker]", minimum: 30
    assert_equal small, large, "the tree ran a notes query per page"
  end

  # Both features that mark a row, each read once for the whole tree
  # (presence plan, Review Focus 5): notes' pill and presence's marker, with
  # a note and two people on every page.
  test "the tree with notes and people on every page costs the same queries for 3 pages as for 30, and marks each row with both" do
    mark_all = lambda do |pages|
      as(users(:two)) { pages.each { |page| Notes::Start.call(page, body: "A note") } }
      pages.each { |page| [ users(:two), users(:reader) ].each { |user| Presence::Mark.arrive(user:, record: page, tab: "tab-#{user.id}-1234567") } }
    end

    mark_all.(add_pages(3, "Small"))
    render_tree # warm up whatever a first render loads once
    small = count_queries { render_tree }

    mark_all.(add_pages(27, "Large"))
    large = count_queries { render_tree }

    assert_selector "span[data-notes-marker]", minimum: 30
    assert_selector "span[data-presence-marker][data-presence-count='2']", count: 30
    assert_equal small, large, "the tree ran a query per page"
  end

  # Presence handoff 10: the marker is the last of the row's markers, after
  # the notes pill, in the row's own 6px gap; every readable row has its
  # element, hidden where nobody is, and a context-only row has none.
  test "each readable row ends its markers with presence's, shown where someone else is here, and the tree is the list its script reads" do
    busy, quiet = add_pages(2, "Row")
    as(users(:two)) { Notes::Start.call(busy, body: "A note") }
    Presence::Mark.arrive(user: users(:two), record: busy, tab: "tab-12345678")
    Presence::Mark.arrive(user: users(:one), record: quiet, tab: "tab-12345678") # the viewer: not company

    render_tree

    assert_selector "turbo-frame#tree[data-controller='admin--pages--tree admin--presence--list'][data-live-part=waiting]" \
                    "[data-admin--presence--list-kind-value=page][data-admin--presence--list-url-value='/cs-studio/presence/here?kind=page']"
    row = "li[data-page-id='#{busy.id}'] > div"
    assert_selector "#{row}.flex.items-center.gap-1\\.5 > [data-notes-marker] + [data-presence-marker='page-#{busy.id}']:not([hidden])"
    assert_selector "#{row} > [data-presence-marker] > [data-presence-marker-label][data-presence-lead='']", text: "#{PersonName.of(users(:two))} is here", exact_text: true
    # Beside the title's link, never inside it.
    assert_no_selector "#{row} a [data-presence-marker]", visible: :all
    assert_selector "li[data-page-id='#{quiet.id}'] > div > [data-presence-marker='page-#{quiet.id}'][hidden]", visible: :all
    assert_selector "[data-presence-marker]", count: Page.kept.count, visible: :all
  end

  # Handoff §10 B24: "↻N" outdated and "○N" missing, summed over the target
  # languages, no box, no "!", the tooltip naming the languages.
  test "a row shows outdated and missing counts summed over the languages, with labels and a tooltip" do
    with_locales(%w[en de es], default: "en") do
      row = create_page(title: "Counted", translations: { "en" => { title: "Counted", subtitle: "Sub" }, "de" => { title: "Gezählt", subtitle: "Unter" } })
      assert Pages::Save.call(row, translations: { "en" => { title: "Counted again", subtitle: "Sub!" } }).ok?
      render_tree

      assert_selector "li[data-page-id='#{row.id}'] > div [data-translation-marker=outdated][role=img]", text: "↻2",
        count: 1
      marker = page_node(row).find("[data-translation-marker=outdated]")
      assert_equal "2 outdated translations: Deutsch", marker["aria-label"]
      assert_equal "Deutsch: 2 outdated", marker["title"]
      missing = page_node(row).find("[data-translation-marker=missing]")
      assert_equal "○1", missing.text
      assert_equal "1 missing translation: Español", missing["aria-label"]
      assert_equal "Español: 1 missing", missing["title"]
      assert_no_selector "[data-translation-marker]", text: "!"
    end
  end

  test "a complete page shows neither count" do
    with_locales(%w[en de], default: "en") do
      done = create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
      render_tree
      assert_no_selector "li[data-page-id='#{done.id}'] > div [data-translation-marker]"
    end
  end

  test "the header names the tree and offers New page" do
    render_tree
    assert_selector "h2", text: "Pages"
    assert_selector "a[href='/cs-studio/pages/new']", text: "+ New page"
  end

  test "the header's New page and each row's + open the New page dialog, the row presetting Inside" do
    about = create_page(title: "About")
    render_tree
    assert_selector "a[href='/cs-studio/pages/new'][data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param=new-page-dialog]", text: "+ New page"
    assert_selector "li[data-page-id='#{about.id}'] > div a[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param=new-page-dialog][data-new-page-parent-id-param='#{about.id}'][href='/cs-studio/pages/new?parent_id=#{about.id}']", visible: :all
  end

  test "the starter offer sits in the header menu only while Home is the only kept page" do
    render_tree
    assert_selector "[role=menu] button", text: "Create starter pages", visible: :all
    create_page(title: "About")
    render_tree
    assert_no_selector "[role=menu] button", text: "Create starter pages", visible: :all
  end

  def page_node(record) = page.find("li[data-page-id='#{record.id}'] > div")

  test "a re-render after one page's save shows that page's new marker and leaves the others alone" do
    with_locales(%w[en de], default: "en") do
      pages = add_pages(4, "Page")
      render_tree

      assert Pages::Save.call(pages.first, translations: { "en" => { title: "Page 0, revised" } }).ok?
      render_tree

      assert_selector "li[data-page-id='#{pages.first.id}'] > div [data-translation-marker=outdated][title*='Deutsch']"
      assert_no_selector "li[data-page-id='#{pages.second.id}'] [data-translation-marker=outdated][title*='Deutsch']"
    end
  end

  test "a live page shows no status chip; a draft does" do
    live = create_page(title: "Live one")
    draft = create_page(title: "Draft one", published: false)
    render_tree
    assert_no_selector "li[data-page-id='#{live.id}'] > div .admin-status-chip"
    assert_selector "li[data-page-id='#{draft.id}'] > div .admin-status-chip", text: "Draft"
  end

  # A row can be without a position (a half-written one; the column takes
  # NULL). The tree sorted its rows in Ruby by the bare column and raised for
  # it, a 500 for the whole Pages screen, where the public site's menu and
  # branch draw such a page last, as Postgres sorts a NULL.
  test "a page without a position is drawn last among its siblings, as the public site orders it, and pages of one position by id" do
    first = create_page(title: "First row")
    lost = create_page(title: "Lost its place")
    second = create_page(title: "Second row")
    twin = create_page(title: "Twin row")
    lost.update_columns(position: nil) # version: none (a test takes a position away, as only a half-written row has none)
    twin.update_columns(position: second.reload.position) # version: none (a test gives two rows one position)

    render_tree

    assert_equal [ "First row", "Second row", "Twin row", "Lost its place" ],
      page.all("#tree a").map(&:text).map(&:strip).select { |text| [ "First row", "Lost its place", "Second row", "Twin row" ].include?(text) }
    branch = PublicSite::Branch.new(urls: PublicSite::Urls.new, locale: "en").under(root_page)
    assert_equal [ first.id, second.id, twin.id, lost.id ], branch.children.map(&:id).select { |id| [ first.id, lost.id, second.id, twin.id ].include?(id) }
  end

  test "a page without children shows no child count" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)
    leaf = create_page(title: "Leaf")
    render_tree
    assert_no_selector "li[data-page-id='#{leaf.id}'] > div [data-child-count]"
    assert_selector "li[data-page-id='#{parent.id}'] > div [data-child-count]", text: "1"
  end

  test "the full title is available as a tooltip when the row truncates" do
    leaf = create_page(title: "A rather long page title that the narrow tree column will cut off")
    render_tree
    assert_selector "li[data-page-id='#{leaf.id}'] > div a[title='#{leaf.title}']"
  end

  test "a live page with unpublished changes carries the mark; a draft with a stale mark does not" do
    live = create_page(title: "Marked live")
    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    draft = create_page(title: "Marked draft", published: false)
    draft.update_columns(unpublished_changes_at: Time.current) # version: none (a test gives a draft a stale mark) # changes: none (a test gives a draft a stale mark)
    create_page(title: "Plain live")

    render_tree

    assert_selector "li[data-page-id='#{live.id}'] > div [data-unpublished-changes][role=img][aria-label='Unpublished changes']"
    assert_no_selector "li[data-page-id='#{draft.id}'] [data-unpublished-changes]"
    assert_selector "[data-unpublished-changes]", count: 1
  end

  test "the mark is a column already loaded: 3 marked pages cost the same queries as 30" do
    mark = lambda do |count, prefix|
      add_pages(count, prefix).each { |page| assert Pages::Save.call(page, translations: { "en" => { title: "#{page.title} typed" } }).ok? }
    end
    mark.call(3, "Small")
    render_tree
    small = count_queries { render_tree }

    mark.call(27, "Large")
    large = count_queries { render_tree }

    assert_selector "[data-unpublished-changes]", count: 30
    assert_equal small, large
  end
end
