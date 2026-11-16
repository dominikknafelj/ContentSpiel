require "test_helper"

# The New folder and Rename folder dialog (the card StudioMediaFolders, D2 and
# D3): the field "Name", where the folder goes under it, the refusal's
# sentences under the field, and Cancel with Create folder or Rename.
class Admin::MediaLibrary::FolderDialogComponentTest < ViewComponent::TestCase
  def folder(name, parent = nil) = Media::Folder.create!(name: name, parent: parent)

  def dialog(**options)
    render_inline Admin::MediaLibrary::FolderDialogComponent.new(tree: Media::FolderTree.load, **options)
  end

  test "the new folder dialog says where the folder goes" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)

    dialog
    assert_selector "dialog#media-folder-dialog[data-dialog-width='form_narrow'][data-controller='admin--media--folder-dialog']", visible: :all
    assert_selector "h2#media-folder-dialog-title", text: "New folder", visible: :all
    assert_selector "form#media-folder-form[action='/cs-studio/media_folders'] input[name=_method][value=post]", visible: :all
    assert_selector "label[for=media-folder-name]", text: "Name", visible: :all
    assert_selector "input#media-folder-name[name='media_folder[name]'][maxlength='80']:not([value])", visible: :all
    assert_selector "input[name='media_folder[parent_id]']:not([value]):not([disabled])", visible: :all
    assert_selector "#media-folder-where.text-small.text-dim", text: "At the top of the library", visible: :all
    assert_selector "#media-folder-where svg[aria-hidden=true]", visible: :all
    assert_selector "footer button", text: "Cancel", visible: :all
    assert_selector "footer button[type=submit][form=media-folder-form]", text: "Create folder", visible: :all

    dialog(parent: client_a)
    assert_selector "#media-folder-where", text: "Inside Clients / Client A", visible: :all
    assert_selector "input[name='media_folder[parent_id]'][value='#{client_a.id}']", visible: :all
  end

  test "the rename dialog fills in the name and says Rename" do
    clients = folder("Clients")
    client_a = folder("Client A", clients)

    dialog(folder: client_a)

    assert_selector "h2#media-folder-dialog-title", text: "Rename folder", visible: :all
    assert_selector "form#media-folder-form[action='/cs-studio/media_folders/#{client_a.id}'] input[name=_method][value=patch]", visible: :all
    assert_selector "input#media-folder-name[value='Client A']", visible: :all
    assert_selector "input[name='media_folder[parent_id]'][disabled]", visible: :all
    assert_selector "#media-folder-where", text: "Inside Clients", visible: :all
    assert_selector "footer button[type=submit]", text: "Rename", visible: :all
    assert_no_selector "footer button", text: "Create folder", visible: :all
  end

  test "a refusal stands under the Name field" do
    sentences = [
      "Give the folder a name.",
      "Use at most 80 characters.",
      "A folder named “Press” is already here.",
      "That would nest folders more than 4 levels deep.",
      "That folder is gone."
    ]

    sentences.each do |sentence|
      dialog(errors: { name: [ sentence ] })

      field = page.find("input#media-folder-name", visible: :all)
      assert_equal "true", field["aria-invalid"]
      assert_includes field["aria-describedby"].split, "media-folder-name-errors"
      # Under the field, before the line saying where.
      assert_selector "input#media-folder-name + #media-folder-name-errors[role=alert] [data-media-folder-error=name]", text: sentence, visible: :all
      assert_selector "#media-folder-name-errors + #media-folder-where", visible: :all
    end

    dialog
    assert_no_selector "input#media-folder-name[aria-invalid]", visible: :all
    assert_no_selector "#media-folder-name-errors p", visible: :all
  end

  test "a parent that is gone is sent again as it was, with no line saying where" do
    render_inline Admin::MediaLibrary::FolderFormComponent.new(tree: Media::FolderTree.load, parent_id: 999_999, errors: { parent_id: [ "That folder is gone." ] })

    assert_selector "input[name='media_folder[parent_id]'][value='999999']", visible: :all
    assert_selector "#media-folder-where[hidden]", visible: :all
    assert_selector "[data-media-folder-error=parent_id]", text: "That folder is gone.", visible: :all
  end
end
