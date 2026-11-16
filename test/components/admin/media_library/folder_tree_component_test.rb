require "test_helper"

# The Folders column of the Media screen (the card StudioMediaFolders, D1):
# All media and Not in a folder, a rule, then the folders in natural order,
# each with its direct count, folded by `cs_media_open` but for the path to
# the place shown.
class Admin::MediaLibrary::FolderTreeComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def render_tree(place: Media::Place::ALL, counts: { all: 0, none: 0, folders: {} }, query: {}, cookie: nil, go_to: nil, manage: true)
    tree = Media::FolderTree.load
    render_inline Admin::MediaLibrary::FolderTreeComponent.new(
      tree: tree, counts: counts, place: place, query: query,
      open_set: TreeOpenSet.parse(cookie, readable_ids: tree.ids), manage: manage, go_to: go_to
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

  test "a folder with no images draws no count" do
    empty = folder("Empty")

    render_tree(counts: { all: 0, none: 0, folders: {} })

    assert_no_selector "[data-media-place='#{empty.id}'] .admin-tree-row__count", visible: :all
    assert_no_selector "[data-media-place='all'] .admin-tree-row__count", visible: :all
    assert_selector "[data-media-place='#{empty.id}']", text: "Empty"
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
end
