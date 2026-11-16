require "test_helper"

# The heading over the Media grid (the card StudioMediaFolders, D10).
class Admin::MediaLibrary::PlaceHeadingComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def heading(place, count: 34, query: {}, **options)
    render_inline Admin::MediaLibrary::PlaceHeadingComponent.new(place: place, tree: Media::FolderTree.load, count: count, query: query, manage: true, **options)
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
end
