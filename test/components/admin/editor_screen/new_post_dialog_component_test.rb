require "test_helper"

# The New post dialog's shell and its form: a Title, a Type select (or, with
# one creatable type, a hidden input) and one primary button, every word a key.
class Admin::EditorScreen::NewPostDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  teardown { I18n.reload! }

  def render_shell(user = users(:one))
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPostDialogComponent.new) }
  end

  def render_form(user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPostFormComponent.new(**options)) }
  end

  def only_now_update_for_branch_editors
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
  end

  test "the shell is a 560 wide dialog with a loading line, an empty frame and a disabled Create draft button" do
    render_shell
    assert_selector "dialog#new-post-dialog[data-dialog-width=form]", visible: :all
    # Its height changes when the form loads into the shell, so it hangs from a fixed
    # top edge like the media picker (`.admin-dialog[data-dialog-hang]`).
    assert_selector "dialog#new-post-dialog[data-dialog-hang]", visible: :all
    assert_selector "#new-post-dialog-title", text: "New post", visible: :all
    assert_selector "[data-admin--editor--new-record-kind-value=post][data-admin--editor--new-record-url-value='/cs-studio/posts/new']", visible: :all
    assert_selector "turbo-frame#new-post-form-frame:empty", visible: :all
    assert_selector "dialog footer button[form=new-post-form][disabled]", text: "Create draft", visible: :all
    assert_no_selector "form#new-post-form", visible: :all
  end

  test "the dialog's words are keys: its title, Loading…, its failures, Try again, Cancel and Create draft" do
    render_shell
    assert_selector "[data-admin--editor--new-record-target=loading]", text: "Loading…", visible: :all
    assert_selector "[data-admin--editor--new-record-target=failure][data-message='The form couldn’t be loaded.'] button", text: "Try again", visible: :all
    assert_selector "[data-admin--editor--new-record-target=submitFailure][data-message='Couldn’t save. Check your connection and try again.']", visible: :all
    assert_selector "dialog footer button", text: "Cancel", visible: :all

    I18n.backend.store_translations(:en, admin: { components: { editor_screen: { new_post_dialog: { create: "Make it", title: "A new one" } } } })
    render_shell
    assert_selector "dialog footer button[form=new-post-form]", text: "Make it", visible: :all
    assert_selector "#new-post-dialog-title", text: "A new one", visible: :all
  end

  test "both dialogs hand the script the same three sentences" do
    expected = {
      "components.editor_screen.new_record.url" => "URL: %{path}",
      "components.editor_screen.new_record.not_listed" => "Not listed on any page yet",
      "components.editor_screen.new_record.page_note" => "Created as a draft at the end of %{title}. Drag it in the tree to move it."
    }
    assert_equal expected.keys, Admin::EditorScreen::NewRecordMessages::KEYS

    [ Admin::EditorScreen::NewPostDialogComponent, Admin::EditorScreen::NewPageDialogComponent ].each do |dialog|
      as(users(:one), channel: :admin) { render_inline(dialog.new) }
      holder = page.find("[data-controller='admin--editor--new-record']", visible: :all)
      assert_equal expected, JSON.parse(holder["data-messages"]).except("@locale"), dialog.name
    end
  end

  test "nothing renders for a viewer who may create no type" do
    render_shell(users(:reader))
    assert_no_selector "dialog", visible: :all
  end

  test "the form: Title first, then a labelled Type select with each type's listing path, the URL line and the draft note" do
    journal = create_page(title: "Journal")
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    publish_changes(journal)
    render_form

    assert_selector "form#new-post-form[action='/cs-studio/posts'][data-turbo-frame='_top']"
    fields = page.all("form#new-post-form input:not([type=hidden]), form#new-post-form select").map { |field| field[:id] }
    assert_equal [ "new-post-title", "new-post-type" ], fields
    assert_selector "label[for=new-post-title]", text: "Title"
    assert_selector "input#new-post-title[name='post[title]'][autofocus]"
    assert_selector "label[for=new-post-type]", text: "Type"
    assert_selector "select#new-post-type[name='post[content_type]'][data-admin--editor--new-record-target=type]"
    assert_equal ContentTypes.all.map(&:name), page.all("select#new-post-type option").map(&:value)
    ContentTypes.all.each { |type| assert_selector "select#new-post-type option[value='#{type.name}']", text: type.label }
    assert_selector "option[value=blog][data-path='/journal']"
    assert_no_selector "option[value=now_update][data-path]"
    assert_no_selector "input[type=radio]", visible: :all
    assert_no_selector ".admin-type-dot"
    assert_selector "[data-admin--editor--new-record-target=url]", text: "URL: /journal/"
    assert_selector "p.text-small", text: "Created as a draft in English. Everything can be changed in the editor."
  end

  test "with one creatable type there is no select: a hidden input carries the type and the note names it" do
    only_now_update_for_branch_editors
    render_form(users(:editor_branch))

    assert_no_selector "select#new-post-type"
    assert_no_selector "label[for=new-post-type]"
    assert_selector "input#new-post-type[type=hidden][name='post[content_type]'][value=now_update][data-admin--editor--new-record-target=type]", visible: :all
    assert_text "Created as a now update draft in English. Everything can be changed in the editor."
  end

  test "the first type is preselected unless one is asked for" do
    render_form
    assert_selector "option[selected]", count: 1
    assert_selector "option[value='#{ContentTypes.all.first.name}'][selected]"

    render_form(content_type: "now_update")
    assert_selector "option[value=now_update][selected]"
    assert_selector "option[selected]", count: 1
  end

  test "only the types the viewer may create are offered" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update", "blog" ] })
    render_form(users(:editor_branch))
    assert_equal %w[blog now_update], page.all("select#new-post-type option").map(&:value).sort
  end

  test "an unlisted type says so; a listed one carries its page's path" do
    render_form
    assert_selector "[data-admin--editor--new-record-target=url]", text: "Not listed on any page yet"

    journal = create_page(title: "Journal")
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    publish_changes(journal)
    render_form
    assert_selector "option[value=blog][data-path='/journal']"
  end

  test "a listing page the viewer can't read keeps its path to itself unless it is live" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "blog" ] })
    journal = create_page(title: "Journal", published: false)
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

    render_form(users(:one))
    assert_selector "option[value=blog][data-path='/journal']"

    render_form(users(:editor_branch))
    assert_selector "input#new-post-type[value=blog]", visible: :all
    assert_no_selector "input#new-post-type[data-path]", visible: :all
    assert_selector "[data-admin--editor--new-record-target=url]", text: "Not listed on any page yet"

    journal.update_columns(published_at: 1.day.ago)
    render_form(users(:editor_branch))
    assert_selector "input#new-post-type[value=blog][data-path='/journal']", visible: :all
  end

  test "the form builds in a constant number of queries however many listing pages there are" do
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { render_form }
      queries
    end
    create_listing = lambda do |title, type|
      ContentBlock.create!(owner: create_page(title: title), block_type: :post_list, position: 0, settings: { "content_type" => type })
    end
    create_listing.call("One", "blog")
    count.call
    one = count.call
    %w[now_update resume_entry].each_with_index { |type, index| create_listing.call("More #{index}", type) }
    4.times { |index| create_listing.call("Extra #{index}", "blog") }
    assert_equal one, count.call
  end

  test "the form alone keeps the typed title and type and shows the summary" do
    post_record = Post.new
    post_record.errors.add(:title, "can't be blank")
    render_form(content_type: "now_update", title: "Typed", errors: post_record.errors)
    assert_selector ".admin-error-summary", text: "1 thing needs fixing"
    assert_selector "option[value=now_update][selected]"
    assert_selector "input#new-post-title[value=Typed][aria-invalid=true]"
  end
end
