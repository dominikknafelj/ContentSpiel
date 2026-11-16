require "test_helper"

# The Folders column of the Media screen (the card StudioMediaFolders, D1):
# All media and Not in a folder, a rule, then the folders in natural order,
# each with its direct count, folded by `cs_media_open` but for the path to
# the place shown.
class Admin::MediaLibrary::FolderTreeComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def render_tree(place: Media::Place::ALL, counts: { all: 0, none: 0, folders: {} }, query: {}, cookie: nil, go_to: nil, manage: true, mode: :screen)
    tree = Media::FolderTree.load
    render_inline Admin::MediaLibrary::FolderTreeComponent.new(
      tree: tree, counts: counts, place: place, query: query,
      open_set: TreeOpenSet.parse(cookie, readable_ids: tree.ids), manage: manage, go_to: go_to, mode: mode
    )
  end

  def place(folder) = Media::Place.new(:folder, folder.id)

  def titles = page.all("#media-folder-tree [data-tree-row]", visible: :all).map { |row| row["data-tree-title"] }

  def row(place_param) = page.find("[data-tree-row][data-media-place='#{place_param}']", visible: :all)

  # The folder's own `<li>`, the node its row stands in.
  def node(folder) = page.find(:xpath, "//li[@data-tree-node][div[@data-media-place='#{folder.id}']]", visible: :all)

  test "the column lists All media, Not in a folder, a rule and the folders in natural order, each with its direct count" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    event_10 = folder("Event 10")
    event_2 = folder("event 2")

    render_tree(counts: { all: 248, none: 61, folders: { clients.id => 4, client_a.id => 34, event_10.id => 7, event_2.id => 3 } })

    assert_selector "div#media-folder-tree-part > ul#media-folder-tree.admin-tree[data-tree-open-cookie='cs_media_open'][data-tree-open-path='/cs-studio']" \
                    "[data-controller='admin--tree--disclosure admin--media--folders']"
    assert_equal [ "All media", "Not in a folder", "Clients", "Client A", "event 2", "Event 10" ], titles
    assert_equal "248", row("all").find(".admin-tree-row__count").text
    assert_equal "61", row("none").find(".admin-tree-row__count").text
    row("all").assert_selector "[data-tree-glyph='media']"
    row("none").assert_selector "[data-tree-glyph='folder_none']"
    # The rule stands after the two places and before the first folder.
    assert_selector "#media-folder-tree > li:nth-child(3).border-t.border-line[aria-hidden='true']"
    assert_selector "#media-folder-tree > li:nth-child(4)[data-tree-node] [data-media-place='#{clients.id}']"
    assert_equal "34", row(client_a.id).find(".admin-tree-row__count", visible: :all).text
    assert_equal "7", row(event_10.id).find(".admin-tree-row__count").text

    client_row = row(client_a.id)
    assert_equal [ "2", "1", clients.id.to_s, "client a" ],
                 %w[data-media-folder-depth data-media-folder-height data-media-folder-parent data-media-folder-name].map { |name| client_row[name] }
    assert_equal [ "1", "2", "" ], %w[data-media-folder-depth data-media-folder-height data-media-folder-parent].map { |name| row(clients.id)[name] }
    # The two places are rows, not nodes: a find over folders leaves them be.
    assert_no_selector "li[data-tree-node] [data-media-place='all']", visible: :all
    assert_no_selector "p", text: "No folders yet."
  end

  # Nothing at 0, but the count's hook is drawn empty, so an upload's answer
  # (`updateCounts`, `media/upload_tiles.js`) can write a row's count into it,
  # from 0 to 1 too; the stylesheet draws an empty count as nothing.
  test "a folder with no images draws no count, and every place's count has its hook" do
    empty = folder("Empty")
    full = folder("Full")

    render_tree(counts: { all: 2, none: 0, folders: { full.id => 2 } })

    { "all" => "2", "none" => "", empty.id.to_s => "", full.id.to_s => "2" }.each do |place, text|
      count = row(place).find(".admin-tree-row__trailing > span.admin-tree-row__count[data-media-place-count='#{place}']", visible: :all)
      assert_equal text, count.text(:all), "the count of #{place}"
    end
    assert_selector "[data-media-place='#{empty.id}']", text: "Empty"
    stylesheet = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_includes stylesheet, ".admin-tree-row__count:empty { display: none; }"
    assert_includes stylesheet, ".admin-tree-row__trailing:not(:has(> :not(.admin-tree-row__count:empty))) { display: none; }"

    render_tree(counts: { all: 2, none: 0, folders: { full.id => 2 } }, mode: :picker)
    assert_selector "#media-picker-folder-tree [data-media-place-count='#{empty.id}']", text: "", visible: :all
    assert_selector "#media-picker-folder-tree [data-media-place-count='all']", text: "2", visible: :all
  end

  test "the place shown is the selected row and its mark is the open folder" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)

    render_tree(place: place(client_a))

    assert_selector ".admin-tree-row--selected", count: 1, visible: :all
    selected = row(client_a.id)
    assert_includes selected[:class], "admin-tree-row--selected"
    selected.assert_selector "a[aria-current='page']", text: "Client A", visible: :all
    # Both marks, the stylesheet showing the open one on the selected row.
    selected.assert_selector ".admin-tree-row__mark > [data-tree-glyph='folder'] + [data-tree-glyph='folder_open']", visible: :all
    assert_not_includes row("all")[:class], "admin-tree-row--selected"
    assert_no_selector "a[aria-current]:not([href*='folder=#{client_a.id}'])", visible: :all

    render_tree(place: Media::Place::NONE)
    assert_includes row("none")[:class], "admin-tree-row--selected"
  end

  test "every row's link keeps q and filter and drops page" do
    clients = folder("Clients")

    render_tree(query: { q: "logo", filter: "unused", page: "3" })

    links = page.all("#media-folder-tree a[data-tree-focus][data-turbo-frame='content'][data-turbo-action='advance']", visible: :all).to_h { |link| [ link.text, link[:href] ] }
    assert_equal "/cs-studio/media?filter=unused&q=logo", links.fetch("All media")
    assert_equal "/cs-studio/media?filter=unused&folder=none&q=logo", links.fetch("Not in a folder")
    assert_equal "/cs-studio/media?filter=unused&folder=#{clients.id}&q=logo", links.fetch("Clients")

    render_tree(query: { q: "", filter: nil })
    assert_selector "a[href='/cs-studio/media'][data-tree-focus]", text: "All media"
  end

  test "folds are drawn from cs_media_open, the path to the place open and every other folder folded" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    folder("2026", client_a)
    events = folder("Events")
    folder("Launch", events)
    team = folder("Team")
    folder("Portraits", team)

    # Clients is folded in the cookie, but is on the path to the place; Team
    # is opened in the cookie; Events and Client A fold by default.
    render_tree(place: place(client_a), cookie: "#{team.id}.-#{clients.id}")

    clients_node = node(clients)
    assert clients_node["data-tree-on-path"], "Clients is not on the path"
    assert_nil clients_node["data-folded"]
    assert_selector "#media-folder-children-#{clients.id}:not([hidden])", visible: :all
    row(clients.id).assert_selector "button[aria-expanded='true'][aria-controls='media-folder-children-#{clients.id}']", visible: :all

    [ client_a, events ].each do |each|
      assert node(each)["data-folded"], "#{each.name} is open"
      assert_selector "#media-folder-children-#{each.id}[hidden]", visible: :all
      row(each.id).assert_selector "button[aria-expanded='false']", visible: :all
    end
    assert_nil node(team)["data-folded"]
    assert_nil node(client_a)["data-tree-on-path"], "the place itself is not on its own path"
  end

  test "with no folders the column says No folders yet." do
    render_tree(counts: { all: 3, none: 3, folders: {} })

    assert_equal [ "All media", "Not in a folder" ], titles
    assert_selector "#media-folder-tree-part > p.text-small.text-dim", text: "No folders yet."
    assert_selector "#media-folder-tree > li.border-t", count: 1
  end

  test "the part carries the place to go to after a write" do
    render_tree(go_to: "/cs-studio/media?folder=none")

    assert_selector "div#media-folder-tree-part[data-media-go='/cs-studio/media?folder=none']"
  end

  test "New folder and the rows' + are for media.manage, on levels 1 to 3" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    year = folder("2026", client_a)
    deepest = folder("Spring", year)

    render_tree(place: place(deepest))

    [ clients, client_a, year ].each do |each|
      add = row(each.id).find("button.admin-tree-row__add", visible: :all)
      assert_equal "New folder in #{each.name}", add["aria-label"]
      assert_equal "admin--ui--dialog#open", add["data-action"]
      assert_equal "media-folder-dialog", add["data-admin--ui--dialog-id-param"]
      assert_equal each.id.to_s, add["data-admin--media--folder-dialog-parent-id-param"]
    end
    assert_equal "Clients / Client A", row(client_a.id).find("button.admin-tree-row__add", visible: :all)["data-admin--media--folder-dialog-parent-path-param"]
    row(deepest.id).assert_no_selector ".admin-tree-row__add", visible: :all
    row("all").assert_no_selector ".admin-tree-row__add", visible: :all
    row("none").assert_no_selector ".admin-tree-row__add", visible: :all

    # The column head's "+ New folder" (the Media screen's view) is the same
    # trigger, for the top.
    assert_equal({ "admin--ui--dialog-id-param": "media-folder-dialog", action: "admin--ui--dialog#open",
                   "admin--media--folder-dialog-parent-id-param": "", "admin--media--folder-dialog-parent-path-param": "" },
                 Admin::MediaLibrary::FolderTreeComponent.add_params(nil, nil))

    render_tree(place: place(deepest), manage: false)
    assert_no_selector ".admin-tree-row__add", visible: :all
  end

  # The handle is a part for the pointer only, in each folder row's gutter:
  # no Tab stop and nothing heard (the keyboard moves a folder by Move to…).
  # All media and Not in a folder never move. The tree names the deepest
  # level, which the drag judges a row by.
  test "the handle is drawn for media.manage only" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)

    render_tree
    assert_selector "ul#media-folder-tree[data-media-drag-tree][data-media-drag-max-depth='#{Media::Folder::MAX_DEPTH}']"
    [ clients, client_a ].each do |each|
      handle = row(each.id).find("span.admin-tree-node__handle[data-media-drag-handle]", visible: :all)
      assert_equal "true", handle["aria-hidden"]
      assert_nil handle["tabindex"]
    end
    assert_no_selector "[data-media-place='all'] .admin-tree-node__handle, [data-media-place='none'] .admin-tree-node__handle", visible: :all

    render_tree(manage: false)
    assert_no_selector ".admin-tree-node__handle", visible: :all
  end

  # The picker's places (the card's D12): D1's rows, read-only, in the
  # picker's own frame. Their folds are a view state: the path to the place
  # is open, every other folder folded, and nothing is read from or written
  # to `cs_media_open` (no `data-tree-open-cookie`, so `tree/open_set.js`
  # has no cookie to write).
  test "in the picker the rows are read-only, keep no folds and load the picker's frame" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    folder("2026", client_a)
    team = folder("Team")
    folder("Portraits", team)

    # Team opened in the cookie: the picker reads none.
    render_tree(place: place(client_a), query: { q: "logo", filter: "unused", page: "2" }, cookie: team.id.to_s, mode: :picker,
                counts: { all: 9, none: 2, folders: { client_a.id => 4 } })

    tree = page.find("nav[aria-label='Folders'] > ul#media-picker-folder-tree.admin-tree", visible: :all)
    assert_equal "admin--tree--disclosure", tree["data-controller"]
    %w[data-tree-open-cookie data-tree-open-path data-media-drag-tree data-media-drag-max-depth].each do |name|
      assert_nil tree[name], "the picker's tree carries #{name}"
    end
    assert_no_selector "#media-folder-tree, #media-folder-tree-part", visible: :all
    assert_no_selector ".admin-tree-row__add, .admin-tree-node__handle, [data-media-drag-handle]", visible: :all
    assert_no_selector "[data-admin--media--folders-target], [data-media-folder-depth], [data-media-folder-height], [data-media-folder-parent], [data-media-folder-name]", visible: :all

    links = page.all("#media-picker-folder-tree a[data-tree-focus][data-turbo-frame='media-picker-grid']", visible: :all).to_h { |link| [ link.text, link[:href] ] }
    assert_equal "/cs-studio/media?filter=unused&picker=1&q=logo", links.fetch("All media")
    assert_equal "/cs-studio/media?filter=unused&folder=none&picker=1&q=logo", links.fetch("Not in a folder")
    assert_equal "/cs-studio/media?filter=unused&folder=#{client_a.id}&picker=1&q=logo", links.fetch("Client A")
    assert_no_selector "#media-picker-folder-tree a[data-turbo-action]", visible: :all

    selected = page.find("#media-picker-folder-tree .admin-tree-row--selected", visible: :all)
    assert_equal "media-picker-place-row-#{client_a.id}", selected[:id]
    assert_equal "4", selected.find(".admin-tree-row__count", visible: :all).text
    assert_nil node(clients)["data-folded"]
    assert node(client_a)["data-folded"], "Client A, the place, keeps its own branch folded"
    assert node(team)["data-folded"], "a fold in cs_media_open reached the picker"
    assert_selector "#media-picker-folder-children-#{team.id}[hidden]", visible: :all
  end

  test "the picker's places are also a select named Folder" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    folder("Events")

    render_tree(place: place(client_a), query: { q: "logo" }, mode: :picker)

    select = page.find_field("Folder", type: "select", visible: :all)
    assert_equal "change->admin--media--picker#place", select["data-action"]
    assert_nil select[:name], "the select is no form's field"
    assert_includes select[:class], "cs-select"
    assert_selector "div.sm\\:hidden select##{select[:id]}", visible: :all
    assert_selector "nav.hidden.sm\\:block", visible: :all

    options = select.all("option", visible: :all)
    assert_equal [ "All media", "Not in a folder", "Clients", "\u00A0\u00A0\u00A0\u00A0Client A", "Events" ], options.map { |option| option.native.text }
    assert_equal [ "all", "none", clients.id.to_s, client_a.id.to_s, folder_id("Events") ], options.map(&:value)
    assert_equal "/cs-studio/media?folder=#{client_a.id}&picker=1&q=logo", options[3]["data-href"]
    assert_equal "/cs-studio/media?picker=1&q=logo", options[0]["data-href"]
    assert_equal [ client_a.id.to_s ], options.select(&:selected?).map(&:value)
  end

  def folder_id(name) = Media::Folder.find_by!(name: name).id.to_s
end
