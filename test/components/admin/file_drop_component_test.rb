require "test_helper"

class Admin::FileDropComponentTest < ViewComponent::TestCase
  test "a labelled drop zone around a visually hidden file input, with a Choose file button" do
    render_inline(Admin::FileDropComponent.new(name: "file", id: "upload", multiple: true, hint: "PNG, JPEG, GIF or WebP, up to 10 MB"))
    assert_selector ".admin-file-drop[data-controller='file-drop']"
    assert_selector "input#upload[type=file][name=file][multiple].sr-only", visible: :all
    assert_selector "label[for=upload]", text: "Choose file"
    assert_text "PNG, JPEG, GIF or WebP, up to 10 MB"
    assert_selector "[data-file-drop-target=name][aria-live=polite]"
  end

  test "accepts the library's image types by default and merges the caller's data attributes onto the input" do
    render_inline(Admin::FileDropComponent.new(name: "file", id: "upload", data: { action: "change->x#y" }))
    assert_selector "input#upload[accept='#{Media::Asset::ALLOWED_CONTENT_TYPES.join(',')}']", visible: :all
    assert_selector "input#upload[data-file-drop-target=input][data-action='change->x#y']", visible: :all
    assert_no_selector "input#upload[multiple]", visible: :all
  end
end
