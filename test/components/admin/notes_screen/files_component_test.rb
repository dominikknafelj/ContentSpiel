require "test_helper"
require "support/note_files_helper"

# The marks that make a message's pictures the image viewer's items
# (`Admin::Ui::ImageViewerComponent`): the box is the group, each picture's
# link an item with what the viewer's head says of it, and a document is no
# item, so the viewer never steps onto it.
class Admin::NotesScreen::FilesComponentTest < ViewComponent::TestCase
  include NoteFilesHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    files = [ fixture_upload("tiny.png", name: "shot.png", declared: "image/png"), note_upload(PDF, "report.pdf", "application/pdf"),
      fixture_upload("small.gif", name: "loop.gif", declared: "image/gif") ]
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Three files", files: files) }.record
    @listing = Notes::Listing.new(@page, viewer: users(:two))
    @note = @listing.find(thread.id).first_message
  end

  test "the box is the message's viewer group; a picture's link is an item with its name and facts, a GIF's marked as one, a document no item" do
    render_inline(Admin::NotesScreen::FilesComponent.new(message: @note, listing: @listing))

    assert_selector "[data-note-files][data-image-viewer-group='#{@note.id}']" do
      assert_selector "a[data-note-image][data-image-viewer-item][data-name='shot.png'][data-facts^='PNG · '][title='View shot.png']", count: 1
      assert_no_selector "a[data-note-image][data-image-viewer-gif]"
      assert_selector "[data-note-gif] a[data-image-viewer-item][data-image-viewer-gif][data-name='loop.gif'][data-facts^='GIF · '][title='View loop.gif']", count: 1
      assert_selector "a[data-note-file]", text: /report\.pdf/, count: 1
      assert_no_selector "a[data-note-file][data-image-viewer-item]"
      assert_selector "[data-image-viewer-item]", count: 2
    end
  end
end
