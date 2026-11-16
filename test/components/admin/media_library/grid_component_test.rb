require "test_helper"

# `Admin::MediaLibrary::GridComponent` on its own: the Media screen's grid and
# the same grid inside the picker. What it decides itself -- each tile's URL
# with the grid's state kept, which tile is selected, which carry Unused (one
# query for the page), the picker's buttons, and the two empty states with a
# list still drawn for an upload to land in. A tile's own markup is
# `TileComponentTest`'s.
class Admin::MediaLibrary::GridComponentTest < ViewComponent::TestCase
  include ContentHelper

  def grid(assets, at: "/cs-studio/media", **options)
    with_request_url(at) { render_inline Admin::MediaLibrary::GridComponent.new(assets: assets, **options) }
  end

  def loaded(*assets) = Media::Asset.with_file.where(id: assets.map(&:id)).order(:id)

  test "one tile per image, each a link to the panel that keeps the grid's own state" do
    first = create_media_asset
    second = create_media_asset(filename: "wide.png")

    grid(loaded(first, second), link_params: { q: "dune", filter: "unused", page: 2 }, url_options: { locale: "de" })

    assert_selector "ul.admin-media-grid > li", count: 2
    href = page.find("#media-asset-#{first.id} a")[:href]
    uri = URI.parse(href)
    assert_equal "/cs-studio/media", uri.path
    assert_equal({ "q" => "dune", "filter" => "unused", "page" => "2", "locale" => "de", "selected" => first.id.to_s }, Rack::Utils.parse_query(uri.query))
    assert_no_selector "[data-media-empty]"
  end

  test "selected_id marks that tile and no other" do
    first = create_media_asset
    second = create_media_asset(filename: "wide.png")

    grid(loaded(first, second))
    assert_no_selector "a[aria-current]"

    grid(loaded(first, second), selected_id: second.id)
    assert_selector "a[aria-current=true]", count: 1
    assert_selector "#media-asset-#{second.id} a.admin-tile[aria-current=true]"
    assert_selector "#media-asset-#{first.id} a.admin-tile:not([aria-current])"
  end

  test "Unused is on the tiles nothing uses, from one query for the whole page" do
    used = create_media_asset
    unused = create_media_asset(filename: "wide.png")
    other = create_media_asset
    owner = create_page(title: "Owner")
    assert Pages::Save.call(owner, attributes: { hero_media_asset_id: used.id }).ok?

    grid(loaded(used, unused, other))

    assert_no_selector "#media-asset-#{used.id}", text: "Unused"
    assert_selector "#media-asset-#{unused.id}", text: "Unused"
    assert_selector "#media-asset-#{other.id}", text: "Unused"

    two = loaded(used, unused).to_a
    three = loaded(used, unused, other).to_a
    assert_equal usage_queries { grid(two) }, usage_queries { grid(three) }
    assert_equal 1, usage_queries { grid(three) }
  end

  test "in the picker a tile is a button to select, not a link to the panel" do
    asset = create_media_asset

    grid(loaded(asset), pick: true)

    assert_selector "#media-picker-asset-#{asset.id} button[type=button][aria-pressed=false]"
    assert_no_selector "#media-asset-#{asset.id}"
    assert_no_selector "ul.admin-media-grid a"
    assert_selector "ul.admin-media-grid.lg\\:grid-cols-6"
  end

  test "an empty library: the list is still drawn for an upload to land in, and the empty state follows it" do
    grid(Media::Asset.none)

    assert_selector "ul.admin-media-grid", count: 1
    assert_no_selector "ul.admin-media-grid > li"
    assert_selector "ul.admin-media-grid + [data-media-empty]", text: "No images"
    assert_text "Upload one above."
    assert_no_link "Clear filters"

    grid(Media::Asset.none, pick: true)
    assert_selector "[data-media-empty]", text: "Use Upload above to add one."
  end

  test "a search or a segment that matches nothing says so and offers Clear filters; a forged segment filters nothing" do
    grid(Media::Asset.none, at: "/cs-studio/media?q=nothing")
    assert_selector "[data-media-empty]", text: "No matches"
    assert_selector "a[href='/cs-studio/media'][data-turbo-frame=content][data-turbo-action=replace]", text: "Clear filters"

    grid(Media::Asset.none, at: "/cs-studio/media?filter=unused")
    assert_text "No images match the current search or filter."

    # Inside the picker the link stays in the picker's own frame and mode.
    grid(Media::Asset.none, at: "/cs-studio/media?picker=1&filter=mine", pick: true)
    assert_selector "a[href='/cs-studio/media?picker=1']:not([data-turbo-frame])", text: "Clear filters"

    grid(Media::Asset.none, at: "/cs-studio/media?filter=forged")
    assert_selector "[data-media-empty]", text: "No images"
    assert_no_link "Clear filters"

    # A non-scalar `q` is no search (and no error).
    grid(Media::Asset.none, at: "/cs-studio/media?q[]=x")
    assert_selector "[data-media-empty]", text: "No images"
  end

  test "the empty states are keys, and the filtered one offers Clear filters" do
    words = I18n.t("admin.components.media_library.grid.empty")

    grid(Media::Asset.none)
    assert_selector "[data-media-empty]", text: words[:title]
    assert_selector "[data-media-empty]", text: words[:description]
    assert_no_link words[:clear]

    grid(Media::Asset.none, pick: true)
    assert_selector "[data-media-empty]", text: words[:picker_description]

    grid(Media::Asset.none, at: "/cs-studio/media?q=nothing")
    assert_selector "[data-media-empty]", text: words[:no_matches]
    assert_selector "[data-media-empty]", text: words[:no_matches_description]
    assert_link words[:clear], href: "/cs-studio/media"
  end

  private

  def usage_queries
    count = 0
    # Cached answers count too: the test runs inside the executor, so a repeated query comes from the query cache.
    counter = ->(*, payload) { count += 1 if payload[:sql].include?("media_usages") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  test "an empty folder offers the upload into it and links its subfolders" do
    clients = folder("Clients")
    year = folder("2026", clients)
    press = folder("Press", clients)
    tree = Media::FolderTree.load

    grid(Media::Asset.none, place: Media::Place.new(:folder, clients.id), tree: tree, subfolders: tree.children(clients.id))

    assert_selector "[data-media-empty] [data-empty-state-title]", text: "No images in this folder yet"
    assert_text "Drop images here, or use Upload images: they go into Clients."
    assert_text "It holds 2 folders: 2026, Press."
    assert_equal [ "2026", "Press" ], page.all("[data-media-empty] a").map(&:text)
    assert_includes page.all("[data-media-empty] a").first[:href], "folder=#{year.id}"
    assert_includes page.all("[data-media-empty] a").last[:href], "folder=#{press.id}"
  end

  test "an empty folder with one subfolder says folder, and with none says nothing of folders" do
    clients = folder("Clients")
    folder("2026", clients)
    tree = Media::FolderTree.load

    grid(Media::Asset.none, place: Media::Place.new(:folder, clients.id), tree: tree, subfolders: tree.children(clients.id))
    assert_text "It holds 1 folder: 2026."

    grid(Media::Asset.none, place: Media::Place.new(:folder, clients.id), tree: tree, subfolders: [])
    assert_no_text "It holds"
  end

  test "an empty Not in a folder says every image is in a folder" do
    grid(Media::Asset.none, place: Media::Place::NONE, tree: Media::FolderTree.load)

    assert_text "Every image is in a folder."
  end

  test "a search that matches nothing in a folder is no matches, not an empty folder" do
    clients = folder("Clients")

    grid(Media::Asset.none, at: "/cs-studio/media?q=zzz", place: Media::Place.new(:folder, clients.id), tree: Media::FolderTree.load)

    assert_text "No matches."
    assert_no_text "No images in this folder yet"
  end

  test "a folder's subfolders are never tiles" do
    clients = folder("Clients")
    folder("2026", clients)
    asset = create_media_asset
    asset.update!(folder_id: clients.id)
    tree = Media::FolderTree.load

    grid(loaded(asset), place: Media::Place.new(:folder, clients.id), tree: tree, subfolders: tree.children(clients.id))

    assert_selector "ul.admin-media-grid > li", count: 1
    assert_no_text "2026"
  end

  test "under a search in All media a tile in a folder names its folder; in a folder's own place none does" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    asset = create_media_asset
    asset.update!(folder_id: client_a.id)
    tree = Media::FolderTree.load

    grid(loaded(asset), at: "/cs-studio/media?q=tiny", tree: tree)
    assert_selector "#media-asset-#{asset.id} [title='Clients / Client A']", text: "Client A"

    grid(loaded(asset), at: "/cs-studio/media", tree: tree)
    assert_no_selector "[title='Clients / Client A']"

    grid(loaded(asset), at: "/cs-studio/media?q=tiny", place: Media::Place.new(:folder, client_a.id), tree: tree)
    assert_no_selector "[title='Clients / Client A']"
  end
end
