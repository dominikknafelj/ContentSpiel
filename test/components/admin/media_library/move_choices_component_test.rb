require "test_helper"

# The Move to… dialog's list (the card StudioMediaFolders, D7): a radiogroup
# named by the dialog's title, its first row "Not in a folder" (images) or
# "Top of the library" (a folder), then every folder with every branch open;
# the current place marked "Current" and not to be chosen; in a folder move,
# the folder's own branch and the too-deep places refused with their reason.
class Admin::MediaLibrary::MoveChoicesComponentTest < ViewComponent::TestCase
  setup do
    @clients = folder("Clients")
    @client_a = folder("Client A", @clients)
    @events = folder("Events")
  end

  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def choices(subject, current: nil, **options)
    render_inline Admin::MediaLibrary::MoveChoicesComponent.new(tree: Media::FolderTree.load, subject: subject, current: current, **options)
  end

  def row_texts = page.all("[role=radiogroup] label").map { |row| row.text.squish }

  def radio(value) = page.find("[role=radiogroup] input[type=radio][value='#{value}']")

  test "images list Not in a folder first and the tree with every branch open" do
    choices({ kind: :images, ids: [ 4, 9 ] }, place: "none", query: { q: "logo" })

    assert_selector "[role=radiogroup][aria-labelledby='media-move-dialog-title']"
    assert_selector "label[for=media-move-find]", text: "Find a folder"
    assert_selector "input[type=search]#media-move-find[placeholder='Find a folder']"
    assert_no_selector "form#media-move-form input[type=search]"
    assert_equal [ "Not in a folder", "Clients", "Client A", "Events" ], row_texts
    assert_selector "[role=radiogroup] label:first-child [data-tree-glyph=folder_none]"
    assert_selector "label.ps-7", text: "Client A"
    assert_selector "label.ps-2", text: "Clients"
    assert_equal "none", radio("none")["value"]
    assert_equal "folder", radio(@client_a.id)["name"]
    assert_no_selector "input[type=radio][disabled]"

    assert_selector "form#media-move-form[action='/cs-studio/media/move'][method=post]"
    assert_equal %w[4 9], page.all("form input[name='asset_ids[]']", visible: :all).map(&:value)
    assert_selector "form input[name=place][value=none]", visible: :all
    assert_selector "form input[name=q][value=logo]", visible: :all
    assert_selector "form input[name=dialog][value=move]", visible: :all
  end

  test "a folder lists Top of the library first" do
    choices({ kind: :folder, folder: @events })

    assert_equal "Top of the library", row_texts.first
    assert_selector "form#media-move-form[action='/cs-studio/media_folders/#{@events.id}'] input[name=_method][value=patch]", visible: :all
    assert_equal "media_folder[parent_id]", radio("")["name"]
    assert_equal "media_folder[parent_id]", radio(@clients.id)["name"]
  end

  test "the current place is marked Current and cannot be chosen" do
    choices({ kind: :images, ids: [ 1 ] }, current: Media::Place.new(:folder, @clients.id))

    current = page.find("[role=radiogroup] label", text: "Clients")
    assert_equal "Clients Current", current.text.squish
    assert current.find("input[type=radio]").disabled?
    badge = current.find("span", text: "Current", exact_text: true)
    assert_equal badge[:id], current.find("input")["aria-describedby"]
    assert_not radio("none").disabled?

    choices({ kind: :images, ids: [ 1 ] }, current: Media::Place::NONE)
    assert radio("none").disabled?
    assert_equal "Not in a folder Current", row_texts.first
  end

  test "a folder move disables itself, its branch and too-deep places with their reason as the description" do
    # Clients holds Client A; moved into Deep 3 (level 3), Client A would
    # stand at level 5. Deep 2 (level 2) still takes it.
    deep1 = folder("Deep 1")
    deep2 = folder("Deep 2", deep1)
    deep3 = folder("Deep 3", deep2)

    choices({ kind: :folder, folder: @clients }, current: Media::Place::NONE)

    { @clients.id => "this folder", @client_a.id => "this folder", deep3.id => "too deep" }.each do |id, reason|
      input = radio(id)
      assert input.disabled?, "#{id} cannot be chosen"
      why = page.find("##{input['aria-describedby']}")
      assert_equal reason, why.text
      assert_includes why[:class], "text-label"
      assert_includes why[:class], "text-meta"
    end
    [ @events.id, deep1.id, deep2.id ].each { |id| assert_not radio(id).disabled?, "#{id} can take it" }
    assert radio("").disabled?, "the top is where it stands"
    assert_equal "Top of the library Current", row_texts.first
  end

  test "a refusal stands on top as a danger notice that can take the focus" do
    choices({ kind: :images, ids: [ 1 ] }, refusal: [ "2 of these images are not yours to move. Nothing was moved." ])

    notice = page.find("#media-move-refusal[role=alert][tabindex='-1']")
    assert_equal "2 of these images are not yours to move. Nothing was moved.", notice.text.squish
    assert_selector "[role=radiogroup]"
  end

  test "a folder gone meanwhile has no list, only its notice" do
    choices({ kind: :folder, folder: Media::Folder.new(id: 0) }, refusal: [ "That folder is gone." ])

    assert_selector "[role=alert]", text: "That folder is gone."
    assert_no_selector "[role=radiogroup]"
    assert_no_selector "form"
  end
end
