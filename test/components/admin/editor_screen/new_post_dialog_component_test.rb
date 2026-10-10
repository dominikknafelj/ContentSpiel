require "test_helper"

# The New post dialog's shell and its form (design pass round 2, Task 15).
class Admin::EditorScreen::NewPostDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_shell(user = users(:one))
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPostDialogComponent.new) }
  end

  def render_form(user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPostFormComponent.new(**options)) }
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

  test "nothing renders for a viewer who may create no type" do
    render_shell(users(:reader))
    assert_no_selector "dialog", visible: :all
  end

  test "the form: a radio card per type with its dot, Title, URL line, draft note" do
    render_form
    assert_selector "form#new-post-form[action='/cs-studio/posts'][data-turbo-frame='_top']"
    ContentTypes.all.each do |type|
      assert_selector "label input[type=radio][name='post[content_type]'][value='#{type.name}']", visible: :all
      assert_selector "label .admin-type-dot", text: type.label
    end
    assert_selector "input#new-post-title[name='post[title]'][autofocus]"
    assert_text "Created as a draft in English. Everything can be changed in the editor."
  end

  test "a chosen card is bold as well as tinted (selection is not colour alone)" do
    render_form
    assert_selector "label[class*='has-checked:font-semibold']"
  end

  test "the first type is preselected unless one is asked for" do
    render_form
    assert_selector "input[type=radio][checked]", count: 1, visible: :all
    assert_selector "input[type=radio][value='#{ContentTypes.all.first.name}'][checked]", visible: :all

    render_form(content_type: "now_update")
    assert_selector "input[type=radio][value=now_update][checked]", visible: :all
    assert_selector "input[type=radio][checked]", count: 1, visible: :all
  end

  test "only the types the viewer may create are offered" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
    render_form(users(:editor_branch))
    assert_equal [ "now_update" ], page.all("input[type=radio]", visible: :all).map { |radio| radio[:value] }
  end

  test "an unlisted type says so; a listed one carries its page's path" do
    render_form
    assert_selector "[data-admin--editor--new-record-target=url]", text: "Not listed on any page yet"

    journal = create_page(title: "Journal")
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    render_form
    assert_selector "input[value=blog][data-path='/journal']", visible: :all
  end

  test "a listing page the viewer can't read keeps its path to itself unless it is live" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "blog" ] })
    journal = create_page(title: "Journal", published: false)
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

    render_form(users(:one))
    assert_selector "input[value=blog][data-path='/journal']", visible: :all

    render_form(users(:editor_branch))
    assert_selector "input[value=blog]", visible: :all
    assert_no_selector "input[value=blog][data-path]", visible: :all
    assert_selector "[data-admin--editor--new-record-target=url]", text: "Not listed on any page yet"

    journal.update_columns(published_at: 1.day.ago)
    render_form(users(:editor_branch))
    assert_selector "input[value=blog][data-path='/journal']", visible: :all
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
    assert_selector "input[value=now_update][checked]", visible: :all
    assert_selector "input#new-post-title[value=Typed][aria-invalid=true]"
  end
end
