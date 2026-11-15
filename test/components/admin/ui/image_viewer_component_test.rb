require "test_helper"

# The image viewer: one empty native dialog, drawn once by the admin layout,
# that `admin--ui--image-viewer` fills from a pressed thumbnail. Its markup
# holds nothing of anyone's files until the script writes it, so these hold
# the parts the script reads by target, closed and empty.
class Admin::Ui::ImageViewerComponentTest < ViewComponent::TestCase
  test "it draws one closed viewer dialog with its stage, arrows, position, actions and announcer" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    assert_selector "dialog#image-viewer[data-dialog-width='viewer'][data-controller~='admin--ui--image-viewer']", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='previous'][aria-label='Previous image'][hidden]", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='next'][aria-label='Next image'][hidden]", visible: :all
    assert_selector "#image-viewer a[data-admin--ui--image-viewer-target='original'][target='_blank']", text: "Open original", visible: :all
    assert_selector "#image-viewer a[data-admin--ui--image-viewer-target='download'][download]", text: "Download", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='announcer'][aria-live='polite']", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='notice'][hidden]", text: "This image couldn't be shown here.", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='loading'][role='status'][hidden] .admin-spinner[aria-hidden='true']", visible: :all
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='loading']", text: "Loading…", visible: :all
    assert_no_selector "#image-viewer img[src]", visible: :all
    # The script writes the links' addresses: an empty viewer has none to offer.
    assert_no_selector "#image-viewer a[href]", visible: :all
  end

  test "it holds no primary button and no Active Storage address" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    refute_includes page.native.to_html, "active_storage"
    refute_includes page.native.to_html, Admin::Ui::ButtonComponent.classes(:primary)
  end

  test "the dialog is named by its title element, the h2 the head truncates" do
    # The h2 is the CSS-truncated title (the viewer step) and the dialog's
    # aria-labelledby, so its whole text is the dialog's name.
    render_inline(Admin::Ui::ImageViewerComponent.new)
    assert_selector "dialog#image-viewer[aria-labelledby='image-viewer-title'] h2#image-viewer-title", visible: :all
  end

  test "the facts stand in the title's aside, and the script's words in data-messages" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    assert_selector "#image-viewer [data-dialog-title-aside] [data-admin--ui--image-viewer-target='facts']", visible: :all
    dialog = page.find("dialog#image-viewer", visible: :all)
    assert_equal %w[components.ui.image_viewer.position components.ui.image_viewer.stepped], (JSON.parse(dialog["data-messages"]).keys - [ "@locale" ]).sort
  end

  test "the stage holds the GIF part, no GIF until the script says, whose picture is also the viewer's" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    frame = page.find("#image-viewer [data-admin--ui--image-viewer-target='stage'] [data-admin--ui--image-viewer-target='frame'][data-controller~='admin--ui--gif']", visible: :all)
    assert_equal "false", frame["data-admin--ui--gif-gif-value"]
    picture = frame.find("img[data-admin--ui--image-viewer-target='picture'][data-admin--ui--gif-target='moving']", visible: :all)
    assert_equal "load->admin--ui--gif#paint error->admin--ui--image-viewer#failed load->admin--ui--image-viewer#loaded", picture["data-action"]
    assert_includes picture[:class].split, "object-contain"
    stage = page.find("#image-viewer [data-admin--ui--image-viewer-target='stage']", visible: :all)
    assert_empty %w[admin-image-viewer__stage bg-sunken relative isolate flex-1 min-h-0 grid place-items-center] - stage[:class].split
  end

  test "the round arrows are 40px popover circles off a phone, the phone's are small secondaries, both with real buttons and the Lucide arrows" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    %w[previous next].each do |target|
      arrow = page.find("#image-viewer [data-admin--ui--image-viewer-target='stage'] button[type=button][data-admin--ui--image-viewer-target='#{target}']", visible: :all)
      assert_empty %w[size-10 rounded-full bg-popover shadow-2 border border-line max-sm:hidden disabled:bg-sunken disabled:text-meta disabled:shadow-none disabled:cursor-not-allowed] - arrow[:class].split
      assert arrow.has_css?("svg[class~='size-[18px]']", visible: :all)
    end
    { "phonePrevious" => "Previous image", "phoneNext" => "Next image" }.each do |target, name|
      arrow = page.find("#image-viewer footer button[type=button][data-admin--ui--image-viewer-target='#{target}'][aria-label='#{name}'][hidden]", visible: :all)
      assert_includes arrow[:class].split, "sm:hidden"
      assert_empty Admin::Ui::ButtonComponent.classes(:secondary, size: :small).split - arrow[:class].split
      assert arrow.has_css?("svg.size-4", visible: :all)
    end
  end

  test "the foot: the position, Open original as a tertiary in a new tab, Download as a secondary" do
    render_inline(Admin::Ui::ImageViewerComponent.new)
    position = page.find("#image-viewer footer [data-admin--ui--image-viewer-target='position']", visible: :all)
    assert_empty %w[text-small text-dim tabular-nums mr-auto] - position[:class].split
    original = page.find("#image-viewer footer a[data-admin--ui--image-viewer-target='original'][rel=noopener]", visible: :all)
    assert_empty Admin::Ui::ButtonComponent.classes(:tertiary).split - original[:class].split
    assert original.has_css?("svg.size-4", visible: :all)
    download = page.find("#image-viewer footer a[data-admin--ui--image-viewer-target='download']", visible: :all)
    assert_empty Admin::Ui::ButtonComponent.classes(:secondary).split - download[:class].split
    assert_selector "#image-viewer [data-admin--ui--image-viewer-target='announcer'].sr-only", visible: :all
  end
end
