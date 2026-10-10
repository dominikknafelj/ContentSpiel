require "test_helper"

# `Media::PickerComponent` (media library design spec §6, Task 8; round 3 Task 9):
# one modal that is the Media grid in miniature -- search and segments in its own
# frame, selectable tiles, a header Upload and a footer "N selected · Cancel ·
# Use image" -- wired to the picker and select controllers on one element.
class Media::PickerComponentTest < ViewComponent::TestCase
  test "renders one dialog wired to the picker and select controllers, with its own grid frame" do
    as(users(:one)) { render_inline Media::PickerComponent.new }

    dialog = page.find("dialog#media-picker", visible: :all)
    assert_equal "admin--media--picker admin--media--select", dialog["data-controller"]
    assert_includes dialog["data-action"], "media-picker:open@window->admin--media--picker#open"
    assert_includes dialog["data-action"], "close->admin--media--picker#closed"
    assert_includes dialog["data-action"], "cancel->admin--media--picker#cancel"
    assert_includes dialog["data-action"], "turbo:frame-load->admin--media--select#reapply"
    assert_includes dialog["data-action"], "admin--media--select:chosen->admin--media--picker#chosen"
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?picker=1", dialog["data-admin--media--picker-grid-url-value"]
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media_assets", dialog["data-admin--media--picker-upload-url-value"]
    assert_selector "turbo-frame#media-picker-grid[data-admin--media--picker-target=frame]", visible: :all
    # The old Library/Upload tabs are gone.
    assert_no_selector "[role=tab]", visible: :all
  end

  test "the header has Upload and a close ×, the footer the selection, Cancel and a disabled Use image" do
    as(users(:one)) { render_inline Media::PickerComponent.new }

    assert_selector "h2", text: "Choose an image", visible: :all
    assert_selector "button[data-action='admin--media--picker#browse']", text: "Upload", visible: :all
    assert_selector "button[aria-label=Close][data-action='admin--media--picker#dismiss']", text: "×", visible: :all
    assert_selector "[role=status][aria-live=polite][data-admin--media--select-target=status]", text: "No image selected", visible: :all
    assert_selector "button[data-action='admin--media--picker#dismiss']", text: "Cancel", visible: :all
    assert_selector "button[disabled][data-admin--media--select-target=use]", text: "Use image", visible: :all
  end

  test "the file input is labelled, multiple, typed, and never part of a form's own data" do
    as(users(:one)) { render_inline Media::PickerComponent.new }

    file = page.find("input[type=file]", visible: :all)
    assert_nil file["name"]
    assert file[:multiple]
    assert_equal Media::Asset::ALLOWED_CONTENT_TYPES.join(","), file["accept"]
    assert_selector "label[for='#{file["id"]}']", text: "Image file", visible: :all
    assert_selector "[role=status][data-admin--media--picker-target=status]", visible: :all
  end

  test "keeps the editing language on the grid's URL" do
    as(users(:one)) { render_inline Media::PickerComponent.new(url_options: { locale: "de" }) }

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?locale=de&picker=1",
      page.find("dialog", visible: :all)["data-admin--media--picker-grid-url-value"]
  end

  # Browsing and choosing need `media.upload` (design spec §5.1); without
  # it no field offers Choose, so there's nothing to render.
  test "renders nothing without media.upload" do
    as(users(:reader)) { render_inline Media::PickerComponent.new }

    assert_no_selector "dialog", visible: :all
  end

  # Its height changes while it is open, so it hangs from a fixed top edge
  # (the fix merged as PR #38); a rule that quietly goes would bring back the
  # jump, so it is pinned next to the New page and New post dialogs' own.
  test "the dialog carries the fixed-top-edge class, and the stylesheet still defines it" do
    as(users(:one)) { render_inline Media::PickerComponent.new }

    assert_selector "dialog.admin-media-picker", visible: :all
    assert_match(/\.admin-media-picker \{ margin-top: 7\.5vh; \}/, Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read)
  end
end
