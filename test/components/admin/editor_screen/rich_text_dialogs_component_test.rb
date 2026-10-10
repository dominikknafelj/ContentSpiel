require "test_helper"

class Admin::EditorScreen::RichTextDialogsComponentTest < ViewComponent::TestCase
  setup { @rendered = -> { as(users(:one)) { render_inline(Admin::EditorScreen::RichTextDialogsComponent.new) } } }

  test "renders the three 560 form dialogs under one controller, none of them open" do
    @rendered.call
    assert_selector "[data-controller='admin--rich-text--dialog']", count: 1
    %w[rich-text-image-dialog rich-text-youtube-dialog rich-text-page-dialog].each do |id|
      assert_selector "dialog##{id}.admin-dialog[data-dialog-width=form]:not([open])", visible: :all
    end
  end

  test "the fields carry no name, so nothing a dialog holds can be submitted with a form" do
    @rendered.call
    assert_no_selector "dialog [name]", visible: :all
    assert_selector "dialog form[data-kind]", count: 3, visible: :all
  end

  test "the image dialog has alt text and caption, each with the Media fallback help, and submit buttons name their form" do
    @rendered.call
    assert_selector "#rich-text-image-dialog label", text: "Alt text", visible: :all
    assert_selector "#rich-text-image-dialog label", text: "Caption", visible: :all
    assert_selector "#rich-text-image-dialog p", text: "Empty uses the text from Media", count: 2, visible: :all
    assert_selector "#rich-text-image-dialog button[type=submit][form=rich-text-image-form]", text: "Insert image", visible: :all
    assert_selector "#rich-text-youtube-dialog button[type=submit][form=rich-text-youtube-form]", text: "Insert video", visible: :all
  end

  test "the YouTube dialog has the URL field with a live status and an error slot" do
    @rendered.call
    assert_selector "#rich-text-youtube-dialog input#rich-text-youtube-url", visible: :all
    assert_selector "#rich-text-youtube-status[role=status]", visible: :all
    assert_selector "#rich-text-youtube-error[role=alert]", visible: :all
  end

  test "the page dialog searches through the link-targets endpoint" do
    @rendered.call
    assert_selector "[data-admin--rich-text--dialog-search-url-value='/cs-studio/link_targets']", visible: :all
    assert_selector "#rich-text-page-dialog input#rich-text-page-search", visible: :all
  end
end
