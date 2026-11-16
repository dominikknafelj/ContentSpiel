require "test_helper"

# The heading over the Media grid (the card StudioMediaFolders, D10).
class Admin::MediaLibrary::PlaceHeadingComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def heading(place, count: 34, query: {}, manage: true, **options)
    render_inline Admin::MediaLibrary::PlaceHeadingComponent.new(place: place, tree: Media::FolderTree.load, count: count, query: query, manage: manage, **options)
  end

  test "a folder's heading is its breadcrumb, its name and its count" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)

    heading(Media::Place.new(:folder, client_a.id), query: { q: "logo", filter: "unused" })

    assert_selector "nav[aria-label='Where you are']"
    links = page.all("nav a")
    assert_equal [ "All media", "Clients" ], links.map(&:text)
    assert_equal "/cs-studio/media?filter=unused&q=logo", links.first[:href].then { |href| href.sub(/\?.*/) { |q| "?" + q.delete_prefix("?").split("&").sort.join("&") } }
    assert_includes links.last[:href], "folder=#{clients.id}"
    assert_includes links.last[:href], "q=logo"
    assert_selector "nav span[aria-current=page]", text: "Client A"
    assert_selector "h1", text: "Client A", count: 1
    assert_selector "#media-place-count.text-small.text-meta", text: "34 images"
    assert_button "Upload images"
  end

  test "one image is said in the singular" do
    heading(Media::Place::ALL, count: 1)

    assert_selector "#media-place-count", text: "1 image"
    assert_no_text "1 images"
  end

  test "All media and Not in a folder are named in the h1 with no breadcrumb" do
    heading(Media::Place::ALL)
    assert_selector "h1", text: "All media"
    assert_no_selector "nav"

    heading(Media::Place::NONE)
    assert_selector "h1", text: "Not in a folder"
    assert_no_selector "nav"
  end

  test "upload: false leaves the button out" do
    heading(Media::Place::ALL, upload: false)

    assert_no_button "Upload images"
  end

  test "the folder menu is for media.manage in a folder, with New folder inside only above level 4" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)
    year = folder("2026", client_a)
    deepest = folder("Spring", year)

    heading(Media::Place.new(:folder, client_a.id))
    menu = page.find("[data-controller='admin--ui--menu']")
    assert_equal "Folder actions", menu.find("button[aria-haspopup=menu]")["aria-label"]
    items = menu.all("[role=menu] button, [role=menu] [role=separator]", visible: :all).map { |item| item[:role] == "separator" ? "-" : item.text(:all) }
    assert_equal [ "New folder inside…", "Rename…", "Move to…", "-", "Delete folder…" ], items
    move = menu.find("button", text: "Move to…", visible: :all)
    assert_equal "media-move-dialog", move["data-admin--ui--dialog-id-param"]
    assert_equal client_a.id.to_s, move["data-admin--media--move-folder-id-param"]
    assert_equal "Client A", move["data-admin--media--move-title-param"]
    assert move.has_css?("svg[aria-hidden=true]", visible: :all)
    inside = menu.find("button", text: "New folder inside…", visible: :all)
    assert_equal client_a.id.to_s, inside["data-admin--media--folder-dialog-parent-id-param"]
    assert_equal "Clients / Client A", inside["data-admin--media--folder-dialog-parent-path-param"]
    rename = menu.find("button", text: "Rename…", visible: :all)
    assert_equal "media-folder-dialog", rename["data-admin--ui--dialog-id-param"]
    assert_equal client_a.id.to_s, rename["data-admin--media--folder-dialog-folder-id-param"]
    assert_equal "Client A", rename["data-admin--media--folder-dialog-folder-name-param"]
    assert_equal "Clients", rename["data-admin--media--folder-dialog-parent-path-param"]
    delete = menu.find("button.text-danger-ink", text: "Delete folder…", visible: :all)
    assert_equal "media-folder-delete-dialog", delete["data-admin--ui--dialog-id-param"]

    heading(Media::Place.new(:folder, deepest.id))
    assert_equal [ "Rename…", "Move to…", "Delete folder…" ], page.all("[role=menu] button", visible: :all).map { |item| item.text(:all) }

    heading(Media::Place.new(:folder, client_a.id), manage: false)
    assert_no_selector "[data-controller='admin--ui--menu']", visible: :all

    heading(Media::Place::ALL)
    assert_no_selector "[data-controller='admin--ui--menu']", visible: :all
    heading(Media::Place::NONE)
    assert_no_selector "[data-controller='admin--ui--menu']", visible: :all
  end
end
