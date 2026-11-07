require "test_helper"

# The page tree's cost profile with translation markers on: the tree is drawn on every editor visit and after every move, so it
# must cost the same handful of queries however many pages (and blocks) it
# shows; its markers are one read of the stored `translation_states`.
class Admin::PagesScreen::TreeComponentTest < ViewComponent::TestCase
  ROW = Admin::Ui::TreeItemComponent::CLASSES

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

  # The tree asks the database for the pages it draws, never for every page
  # and every column: a trashed page and a page the viewer may not see are
  # not loaded at all, and the row reads only `PageTree::COLUMNS`.
  test "the tree reads only kept, visible pages, and only the tree's columns" do
    kept = create_page(title: "Kept")
    trashed = create_page(title: "Thrown away")
    assert Trash::Move.call(trashed).ok?
    root = root_page.reload

    statements = capture_sql { render_inline(Admin::PagesScreen::TreeComponent.new(root: root, locale: "en")) }

    assert_empty statements.grep(/SELECT "pages"\.\* FROM "pages"/), "the tree read every column of pages"
    assert statements.any? { |sql| sql.match?(/"pages"\."id" IN/) }, "the tree did not narrow its pages to the visible ids in SQL:\n#{statements.join("\n")}"
    assert_selector "li[data-page-id='#{kept.id}']"
    assert_no_selector "li[data-page-id='#{trashed.id}']"
  end

  test "the tree with translation markers costs the same queries for 3 pages as for 30" do
    with_locales(%w[en de es], default: "en") do
      add_pages(3, "Small")
      render_tree # warm up whatever a first render loads once
      small = count_statements { render_tree }

      add_pages(27, "Large")
      large = count_statements { render_tree }

      assert_selector "li.admin-tree-node", minimum: 31
      assert_equal small, large, "the tree ran a query per page"
    end
  end

  test "the tree with open notes on its pages costs the same queries for 3 pages as for 30, and draws a pill on each" do
    add_notes = ->(pages) { as(users(:two)) { pages.each { |page| Notes::Start.call(page, body: "A note") } } }

    small_pages = add_pages(3, "Small")
    add_notes.(small_pages)
    render_tree # warm up whatever a first render loads once
    small = count_statements { render_tree }

    large_pages = add_pages(27, "Large")
    add_notes.(large_pages)
    large = count_statements { render_tree }

    assert_selector "span[data-notes-marker]", minimum: 30
    assert_equal small, large, "the tree ran a notes query per page"
  end

  # Both features that mark a row, each read once for the whole tree:
  # notes' pill and presence's marker, with a note and two people on every
  # page.
  test "the tree with notes and people on every page costs the same queries for 3 pages as for 30, and marks each row with both" do
    mark_all = lambda do |pages|
      as(users(:two)) { pages.each { |page| Notes::Start.call(page, body: "A note") } }
      pages.each { |page| [ users(:two), users(:reader) ].each { |user| Presence::Mark.arrive(user:, record: page, tab: "tab-#{user.id}-1234567") } }
    end

    mark_all.(add_pages(3, "Small"))
    render_tree # warm up whatever a first render loads once
    small = count_statements { render_tree }

    mark_all.(add_pages(27, "Large"))
    large = count_statements { render_tree }

    assert_selector "span[data-notes-marker]", minimum: 30
    assert_selector "span[data-presence-marker][data-presence-count='2']", count: 30
    assert_equal small, large, "the tree ran a query per page"
  end

  # Presence's marker is the last of the row's markers, after the notes
  # pill, among the row's trailing parts; every readable row has its
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
    assert_selector "#{row}.#{ROW[:row]} > .#{ROW[:trailing]} > [data-notes-marker] + [data-presence-marker='page-#{busy.id}']:not([hidden])"
    assert_selector "#{row} [data-presence-marker] > [data-presence-marker-label][data-presence-lead='']", text: "#{PersonName.of(users(:two))} is here", exact_text: true
    # Beside the title's link, never inside it.
    assert_no_selector "#{row} a [data-presence-marker]", visible: :all
    assert_selector "li[data-page-id='#{quiet.id}'] > div [data-presence-marker='page-#{quiet.id}'][hidden]", visible: :all
    assert_selector "[data-presence-marker]", count: Page.kept.count, visible: :all
  end

  # "↻N" outdated and "○N" missing, summed over the target languages, no
  # box, no "!", the tooltip naming the languages.
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

  test "the head, the drag help and the empty line are keys" do
    assert_equal "Pages", I18n.t("admin.components.pages_screen.tree.heading") # the files are loaded, so what is stored stays
    I18n.backend.store_translations(:en, admin: { components: { pages_screen: { tree: {
      heading: "Seiten", new_page: "+ Neue Seite", more_actions: "Weitere Aktionen", starter_pages: "Startseiten anlegen",
      drag_help: "Leertaste zum Aufnehmen", empty: "Noch keine Seiten."
    } } } })

    render_tree
    assert_selector "h2", text: "Seiten", exact_text: true
    assert_selector "a[href='/cs-studio/pages/new']", text: "+ Neue Seite", exact_text: true
    assert_selector "button[aria-label='Weitere Aktionen']"
    assert_selector "[role=menu] button", text: "Startseiten anlegen", visible: :all
    assert_selector "#tree-drag-help", text: "Leertaste zum Aufnehmen", exact_text: true, visible: :all

    render_inline(Admin::PagesScreen::TreeComponent.new(root: nil, locale: "en"))
    assert_text "Noch keine Seiten."
  ensure
    I18n.reload!
  end

  # `admin--pages--tree` announces a keyboard move in these words, read from
  # the frame (`i18n/messages.js`), and names a row without a title by the
  # row's own fallback.
  test "the frame hands the script its move words" do
    render_tree

    words = JSON.parse(page.find("turbo-frame#tree")["data-messages"])
    %w[picked_up dropped position cancelled].each do |key|
      assert_equal I18n.t("admin.components.pages_screen.tree.moves.#{key}"), words.fetch("components.pages_screen.tree.moves.#{key}"), key
    end
    assert_equal "(untitled)", words.fetch("components.pages_screen.tree_row.untitled")
    assert_includes words.fetch("components.pages_screen.tree.moves.picked_up"), "%{title}"
    assert_no_selector "turbo-frame#tree[data-admin--pages--tree-selected-title-class]"
  end

  # A find matches a row by its title or, from "/", by its address in the
  # editing language; both are on the row, with the page's bare id. A
  # context-only row is matched by its title alone.
  test "each row carries its title and its address for find" do
    with_locales(%w[en de], default: "en") do
      about = create_page(title: "About", translations: { "de" => { title: "Über uns" } })
      team = create_page(title: "Team", parent: about)

      render_tree
      assert_selector "#tree-row-#{root_page.id}[data-tree-row][data-tree-title='#{root_page.title}'][data-tree-path='/'][data-tree-id='#{root_page.id}']"
      assert_selector "#tree-row-#{about.id}[data-tree-title='About'][data-tree-path='/about'][data-tree-id='#{about.id}']"
      assert_selector "#tree-row-#{team.id}[data-tree-title='Team'][data-tree-path='/about/team']"
      assert_selector "ul#tree-list.#{ROW[:tree]} > li[data-tree-node][data-page-id='#{root_page.id}']"

      render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, locale: "de"))
      assert_selector "#tree-row-#{about.id}[data-tree-title='Über uns'][data-tree-path='#{PublicSite::Paths.current_path(about, "de")}']"
    end
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

  # A mark after the title only when a page is not simply live, named for a
  # screen reader in the status chip's and the unpublished chip's own words.
  test "a draft is a hollow meta ring, a scheduled page a warn dot, a live page with changes a dim dot, and a live page nothing" do
    draft = create_page(title: "Draft one", published: false)
    soon = create_page(title: "Soon")
    soon.update_columns(published_at: 2.days.from_now) # version: none (a test schedules a page) # changes: none (a test schedules a page)
    changed = create_page(title: "Changed")
    assert Pages::Save.call(changed, translations: { "en" => { title: "Changed typed" } }).ok?
    plain = create_page(title: "Plain")

    render_tree

    assert_selector "li[data-page-id='#{draft.id}'] > div > .#{ROW[:state]} > .admin-tree-mark[data-status=draft][role=img][aria-label='Draft'][title='Draft'][class~='border-meta'][class~='border-[1.5px]'][class~='size-1.5']"
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[data-status=scheduled][aria-label='Scheduled'][class~='bg-warn']"
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[title^='Scheduled · ']"
    assert_selector "li[data-page-id='#{changed.id}'] > div .admin-tree-mark[data-unpublished-changes][aria-label='Unpublished changes'][class~='bg-dim']"
    assert_no_selector "li[data-page-id='#{plain.id}'] > div .admin-tree-mark"
    assert_no_selector "li[data-page-id='#{plain.id}'] > div > .#{ROW[:state]}", visible: :all
    assert_no_selector ".admin-status-chip"
  end

  # One mark a row: a scheduled page with unpublished changes draws the
  # scheduled dot, named for both states.
  test "a scheduled page with unpublished changes has one mark that names both" do
    soon = create_page(title: "Soon")
    soon.update_columns(published_at: 2.days.from_now, unpublished_changes_at: Time.current) # version: none (a test schedules a page) # changes: none (a test marks a scheduled page)

    render_tree

    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark", count: 1
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[data-status=scheduled][data-unpublished-changes][aria-label='Scheduled · Unpublished changes'][class~='bg-warn']"
  end

  test "the selected row carries the accent bar's class and no inline shadow" do
    chosen = create_page(title: "Chosen")
    render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: chosen, locale: "en"))
    row = page.find("li[data-page-id='#{chosen.id}'] > div", match: :first)
    assert_includes row[:class].split, "admin-tree-row--selected"
    assert_no_match(/shadow-/, row[:class])
  end

  # The selection's ground, bar and title weight are the tree's selected
  # rule (`.admin-tree-row--selected`): the row adds no utility for them.
  test "the selected row is the tree's selected row, and its title link takes no weight of its own" do
    chosen = create_page(title: "Chosen")
    other = create_page(title: "Other")
    render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: chosen, locale: "en"))

    assert_equal [ ROW[:row], ROW[:row_selected] ], page.find("li[data-page-id='#{chosen.id}'] > div")[:class].split
    assert_selector "li[data-page-id='#{chosen.id}'] > div > .#{ROW[:title]} > a#tree-link-#{chosen.id}[aria-current=page]:not([class])"
    assert_equal [ ROW[:row] ], page.find("li[data-page-id='#{other.id}'] > div")[:class].split
  end

  HIDDEN_AT_REST = [ ROW[:reveal] ].freeze

  test "a row's translation markers are hidden at rest but read, and shown on the selected row" do
    with_locales(%w[en de es], default: "en") do
      row = create_page(title: "Counted", translations: { "en" => { title: "Counted", subtitle: "Sub" }, "de" => { title: "Gezählt", subtitle: "Unter" } })
      assert Pages::Save.call(row, translations: { "en" => { title: "Counted again", subtitle: "Sub!" } }).ok?
      render_tree

      %w[outdated missing].each do |kind|
        marker = page_node(row).find("[data-translation-marker=#{kind}]")
        classes = marker[:class].split
        HIDDEN_AT_REST.each { |token| assert_includes classes, token }
        assert_includes classes, "text-count"
        assert_equal "img", marker[:role]
        assert marker["aria-label"].present?
        assert_no_match(/\bhidden\b/, marker[:class])
        assert_nil marker["aria-hidden"]
      end

      render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: row, locale: "en"))
      %w[outdated missing].each do |kind|
        classes = page_node(row).find("[data-translation-marker=#{kind}]")[:class].split
        HIDDEN_AT_REST.each { |token| assert_not_includes classes, token }
      end
    end
  end

  # The tree's SQL read comes in the order the tree is drawn in, and both are
  # `TreeOrder`'s, which the mind graph and the public branch share: over a
  # nested tree with a page without a position and two pages of one position,
  # each parent's children read, sorted by `TreeOrder` and drawn are one list.
  test "the tree's read, TreeOrder and the drawn tree give each parent's children in one order" do
    parent = create_page(title: "Parent")
    children = 4.times.map { |index| create_page(title: "Child #{index}", parent: parent) }
    create_page(title: "Sibling")
    children[0].update_columns(position: nil) # version: none (a test takes a position away, as only a half-written row has none)
    children[3].update_columns(position: children[1].reload.position) # version: none (a test gives two rows one position)

    render_tree

    read = PageTree.rows(Page.kept.ids).to_a.group_by(&:parent_id)
    assert_operator read.size, :>=, 2
    read.each do |parent_id, pages|
      assert_equal TreeOrder.sort(pages).map(&:id), pages.map(&:id), "the read's order under page #{parent_id}"
      drawn = page.all("ul[data-parent-id='#{parent_id}'] > li", visible: :all).map { |node| node["data-page-id"].to_i }
      assert_equal pages.map(&:id), drawn, "the drawn order under page #{parent_id}" if parent_id
    end
    assert_equal children.values_at(1, 3, 2, 0).map(&:id), read.fetch(parent.id).map(&:id)
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

  # One level is `--cs-tree-step`, drawn by `.admin-tree__children` alone:
  # a children list carries the tree's class and its hooks, never a margin
  # or padding of its own, and the parent's disclosure names it.
  test "a level is the tree's step: each children list is a data-tree-children list with no indent class of its own" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)
    render_tree

    lists = page.all("ul[data-parent-id]", visible: :all)
    assert_operator lists.size, :>=, 3
    lists.each do |list|
      assert_equal [ ROW[:children] ], list[:class].split, "a children list is the tree's step and nothing else"
      assert_equal "tree-children-#{list["data-parent-id"]}", list[:id]
      assert list["data-tree-children"], "a children list is the scripts' data-tree-children"
    end
    disclosure = page.find("#tree-row-#{parent.id} > button.#{ROW[:disclosure]}")
    assert_equal "tree-children-#{parent.id}", disclosure["aria-controls"]
    assert_equal "true", disclosure["aria-expanded"]
    assert_nil disclosure["data-action"], "the disclosure folds nothing yet"
    assert_no_selector "li[data-page-id='#{parent.children.first.id}'] > div > button.#{ROW[:disclosure]}"
  end

  test "the drag handle stands in the row's gutter by the tree's own classes, and rests transparent" do
    alpha = create_page(title: "Alpha")
    render_tree

    handle = page.find("li[data-page-id='#{alpha.id}'] > div > button[aria-label='Move Alpha'][aria-describedby=tree-drag-help]")
    assert_equal [ ROW[:handle] ], handle[:class].split
    # The homepage has no handle and no gutter to put one in.
    assert_no_selector "li[data-page-id='#{root_page.id}'] > div .#{ROW[:handle]}"
  end

  test "the subpage count is the tree's count, hidden at rest by the tree's rule and never removed" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)
    render_tree

    count = page.find("li[data-page-id='#{parent.id}'] > div > .#{ROW[:trailing]} > [data-child-count][role=img][aria-label='1 subpage']", visible: :all)
    assert_equal [ ROW[:count], ROW[:reveal] ], count[:class].split
    assert_nil count[:hidden]
    assert_nil count["aria-hidden"]
  end

  test "the full title is available as a tooltip when the row truncates" do
    leaf = create_page(title: "A rather long page title that the narrow tree column will cut off")
    render_tree
    assert_selector "li[data-page-id='#{leaf.id}'] > div > .#{ROW[:title]}[title='#{leaf.title}'] > a"
  end

  # "+" is the shared row's own part, last in the row: the Pages row names
  # it and hands it the dialog's trigger, and gives it no class of its own.
  test "a row's + is the tree's own part, named by the row, with no class of its own" do
    about = create_page(title: "About")
    render_tree

    add = page.find("li[data-page-id='#{about.id}'] > div > a.#{ROW[:add]}:last-child[aria-label='Add a page under About']")
    assert_equal [ ROW[:add] ], add[:class].split
    assert_equal "new-page-dialog", add["data-admin--ui--dialog-id-param"]
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
    small = count_statements { render_tree }

    mark.call(27, "Large")
    large = count_statements { render_tree }

    assert_selector "[data-unpublished-changes]", count: 30
    assert_equal small, large
  end
end
