require "test_helper"

# `Media::PickerComponent` (media library design spec §6, Task 8): one modal
# with a Library tab (the Media module's own listing, `picker=1`, loaded
# into a frame on open) and an Upload tab (the JSON upload endpoint).
class Media::PickerComponentTest < ViewComponent::TestCase
  test "renders one dialog with Library and Upload tabs wired to the picker controller" do
    as(users(:one)) { render_inline Media::PickerComponent.new }

    dialog = page.find("dialog#media-picker", visible: :all)
    assert_equal "admin--media-picker", dialog["data-controller"]
    assert_includes dialog["data-action"], "media-picker:open@window->admin--media-picker#open"
    assert_includes dialog["data-action"], "close->admin--media-picker#closed"
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?picker=1", dialog["data-admin--media-picker-library-url-value"]
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media_assets", dialog["data-admin--media-picker-upload-url-value"]

    assert_selector "[role=tab][aria-selected=true]", text: "Library", visible: :all
    assert_selector "[role=tab][aria-selected=false]", text: "Upload", visible: :all
    assert_selector "turbo-frame#media-picker-library", visible: :all
    file = page.find("input[type=file]", visible: :all)
    assert_nil file["name"] # never part of any form's own data
    assert_equal Media::Asset::ALLOWED_CONTENT_TYPES.join(","), file["accept"]
    assert_selector "[role=alert][data-admin--media-picker-target=error]", visible: :all
  end

  test "keeps the editing language on the Library tab's URL" do
    as(users(:one)) { render_inline Media::PickerComponent.new(url_options: { locale: "de" }) }

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?locale=de&picker=1",
      page.find("dialog", visible: :all)["data-admin--media-picker-library-url-value"]
  end

  # Browsing and choosing need `media.upload` (design spec §5.1); without
  # it no field offers Choose, so there's nothing to render.
  test "renders nothing without media.upload" do
    as(users(:reader)) { render_inline Media::PickerComponent.new }

    assert_no_selector "dialog", visible: :all
  end
end
