require "test_helper"

# The New page and New post dialogs' shell: a 560 wide dialog per kind with a
# loading line, an empty frame and a disabled Create button, every word a key.
# The forms loaded into it are the editor screen's (`new_page_form_component_test.rb`,
# `new_post_form_component_test.rb`).
class Admin::Ui::NewRecordDialogComponentTest < ViewComponent::TestCase
  # Tests here store words into the shared backend, and reloading in teardown
  # puts the files' translations back. A reload leaves the backend empty until
  # its next lookup, which loads the files OVER whatever was stored before it,
  # so every test starts with the files loaded and a store always wins.
  setup { I18n.backend.eager_load! }
  teardown { I18n.reload! }

  def render_shell(kind, user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::Ui::NewRecordDialogComponent.new(kind:, **options)) }
  end

  test "the page shell is a 560 wide dialog with a loading line, an empty frame and a disabled Create page button" do
    render_shell(:page)
    assert_selector "dialog#new-page-dialog[data-dialog-width=form]", visible: :all
    # Its height changes when the form loads into the shell, so it hangs from a fixed
    # top edge like the media picker (`.admin-dialog[data-dialog-hang]`).
    assert_selector "dialog#new-page-dialog[data-dialog-hang]", visible: :all
    assert_selector "#new-page-dialog-title", text: "New page", visible: :all
    assert_selector "[data-controller=admin--editor--new-record][data-admin--editor--new-record-kind-value=page][data-admin--editor--new-record-url-value='/cs-studio/pages/new']", visible: :all
    assert_selector "[data-admin--editor--new-record-target=loading]", text: "Loading…", visible: :all
    assert_selector "[data-admin--editor--new-record-target=failure][hidden] button", text: "Try again", visible: :all
    assert_selector "turbo-frame#new-page-form-frame:empty", visible: :all
    assert_selector "dialog footer button[form=new-page-form][disabled]", text: "Create page", visible: :all
    assert_selector "dialog footer button", text: "Cancel", visible: :all
    assert_no_selector "form#new-page-form", visible: :all
  end

  test "the post shell is a 560 wide dialog with a loading line, an empty frame and a disabled Create draft button" do
    render_shell(:post)
    assert_selector "dialog#new-post-dialog[data-dialog-width=form]", visible: :all
    assert_selector "dialog#new-post-dialog[data-dialog-hang]", visible: :all
    assert_selector "#new-post-dialog-title", text: "New post", visible: :all
    assert_selector "[data-admin--editor--new-record-kind-value=post][data-admin--editor--new-record-url-value='/cs-studio/posts/new']", visible: :all
    assert_selector "turbo-frame#new-post-form-frame:empty", visible: :all
    assert_selector "dialog footer button[form=new-post-form][disabled]", text: "Create draft", visible: :all
    assert_no_selector "form#new-post-form", visible: :all
  end

  test "the form ids the Create buttons name are the forms' own" do
    assert_equal Admin::EditorScreen::NewPageFormComponent::FORM_ID, Admin::Ui::NewRecordDialogComponent::KINDS.fetch(:page).form_id
    assert_equal Admin::EditorScreen::NewPostFormComponent::FORM_ID, Admin::Ui::NewRecordDialogComponent::KINDS.fetch(:post).form_id
  end

  test "the URL options reach the form's address" do
    render_shell(:post, url_options: { locale: "de" })
    assert_selector "[data-admin--editor--new-record-url-value='/cs-studio/posts/new?locale=de']", visible: :all
  end

  test "an unknown kind is refused" do
    assert_raises(ArgumentError) { Admin::Ui::NewRecordDialogComponent.new(kind: :tag) }
  end

  test "the dialog's words are keys: its title, Loading…, its failures, Try again, Cancel and Create" do
    render_shell(:post)
    assert_selector "[data-admin--editor--new-record-target=loading]", text: "Loading…", visible: :all
    assert_selector "[data-admin--editor--new-record-target=failure][data-message='The form couldn’t be loaded.'] button", text: "Try again", visible: :all
    assert_selector "[data-admin--editor--new-record-target=submitFailure][data-message='Couldn’t save. Check your connection and try again.']", visible: :all
    assert_selector "dialog footer button", text: "Cancel", visible: :all

    I18n.backend.store_translations(:en, admin: { components: { ui: { new_record_dialog: { post: { create: "Make it", title: "A new one" } } } } })
    render_shell(:post)
    assert_selector "dialog footer button[form=new-post-form]", text: "Make it", visible: :all
    assert_selector "#new-post-dialog-title", text: "A new one", visible: :all
  end

  test "both kinds hand the script the same three sentences" do
    expected = {
      "components.editor_screen.new_record.url" => "URL: %{path}",
      "components.editor_screen.new_record.not_listed" => "Not listed on any page yet",
      "components.editor_screen.new_record.page_note" => "Created as a draft at the end of %{title}. Drag it in the tree to move it."
    }
    assert_equal expected.keys, Admin::Ui::NewRecordDialogComponent::MESSAGES

    %i[post page].each do |kind|
      render_shell(kind)
      holder = page.find("[data-controller='admin--editor--new-record']", visible: :all)
      assert_equal expected, JSON.parse(holder["data-messages"]).except("@locale"), kind
    end
  end

  test "the shell runs no query for pages and renders for a viewer who holds the right anywhere" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/FROM "pages"|public_paths/) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { render_shell(:page) }
    assert_empty queries
  end

  test "nothing renders for a viewer who may create no page, or no type" do
    render_shell(:page, users(:reader))
    assert_no_selector "dialog", visible: :all
    render_shell(:post, users(:reader))
    assert_no_selector "dialog", visible: :all
  end
end
