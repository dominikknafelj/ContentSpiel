require "test_helper"

class Admin::PostsScreen::BulkBarComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a hidden bar with the count, Publish, Move to trash and Clear, and an always-present polite status beside it" do
    render_inline Admin::PostsScreen::BulkBarComponent.new(list_fields: { "q" => "x", "scope" => "drafts" })
    assert_selector "[hidden][data-admin--bulk-select-target=bar]:not([aria-live])", visible: :all
    assert_selector "p.sr-only[role=status][aria-live=polite][aria-atomic=true][data-admin--bulk-select-target=status]", visible: :all
    assert_selector "[data-admin--bulk-select-target=count]", text: "0", visible: :all
    assert_selector "[data-admin--bulk-select-target=bar] button[data-action='admin--bulk-select#clear']", text: "Clear", visible: :all
    assert_selector "button[data-admin--ui--dialog-id-param=bulk-trash-dialog]", text: "Move to trash", visible: :all
  end

  test "Publish and the trash confirmation are separate forms that repeat the list's filters and hold an ids container" do
    render_inline Admin::PostsScreen::BulkBarComponent.new(list_fields: { "q" => "x", "scope" => "drafts" })
    assert_selector "form[action='/cs-studio/posts/bulk'][data-turbo-frame=_top]", count: 2, visible: :all
    assert_selector "form input[name=bulk_action][value=publish]", visible: :all
    assert_selector "dialog#bulk-trash-dialog form input[name=bulk_action][value=trash]", visible: :all
    assert_selector "form input[name=q][value=x]", count: 2, visible: :all
    assert_selector "form input[name=scope][value=drafts]", count: 2, visible: :all
    assert_selector "form [data-admin--bulk-select-target=ids]", count: 2, visible: :all
    # Never nested: the dialog's form is not inside the Publish form.
    assert_no_selector "form form", visible: :all
  end

  test "the trash confirmation is destructive and names the count" do
    render_inline Admin::PostsScreen::BulkBarComponent.new
    assert_selector "dialog#bulk-trash-dialog [data-admin--bulk-select-target=confirmCount]", text: "0 posts", visible: :all
    assert_selector "dialog#bulk-trash-dialog button[autofocus]", text: "Cancel", visible: :all
    assert_selector "dialog#bulk-trash-dialog button.bg-danger", text: "Move to trash", visible: :all
  end

  test "only what the viewer holds is offered, and nothing renders when it is neither" do
    Current.actor = users(:author) # Author group: no posts.publish, no posts.delete
    render_inline Admin::PostsScreen::BulkBarComponent.new
    assert_no_selector "[data-admin--bulk-select-target=bar]", visible: :all
  end
end
