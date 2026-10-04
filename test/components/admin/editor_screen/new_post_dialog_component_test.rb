require "test_helper"

# The New post dialog (design pass round 2, Task 15).
class Admin::EditorScreen::NewPostDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_dialog(user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPostDialogComponent.new(**options)) }
  end

  test "a 560 wide dialog: a radio card per type with its dot, Title, URL line, draft note" do
    render_dialog
    assert_selector "dialog#new-post-dialog[data-dialog-width=form]", visible: :all
    assert_selector "#new-post-dialog-title", text: "New post", visible: :all
    assert_selector "form#new-post-form[action='/cs-studio/posts'][data-turbo-frame='_top']", visible: :all
    ContentTypes.all.each do |type|
      assert_selector "label input[type=radio][name='post[content_type]'][value='#{type.name}']", visible: :all
      assert_selector "label .admin-type-dot", text: type.label, visible: :all
    end
    assert_selector "input#new-post-title[name='post[title]'][autofocus]", visible: :all
    assert_selector "dialog footer button[form=new-post-form]", text: "Create draft", visible: :all
    assert_selector "dialog", text: "Created as a draft in English. Everything can be changed in the editor.", visible: :all
  end

  test "the first type is preselected unless one is asked for" do
    render_dialog
    assert_selector "input[type=radio][checked]", count: 1, visible: :all
    assert_selector "input[type=radio][value='#{ContentTypes.all.first.name}'][checked]", visible: :all

    as(users(:one), channel: :admin) { render_inline(Admin::EditorScreen::NewPostFormComponent.new(content_type: "now_update")) }
    assert_selector "input[type=radio][value=now_update][checked]"
    assert_selector "input[type=radio][checked]", count: 1
  end

  test "only the types the viewer may create are offered" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
    render_dialog(users(:editor_branch))
    assert_equal [ "now_update" ], page.all("input[type=radio]", visible: :all).map { |radio| radio[:value] }
  end

  test "nothing renders for a viewer who may create no type" do
    render_dialog(users(:reader))
    assert_no_selector "dialog", visible: :all
  end

  test "an unlisted type says so; a listed one carries its page's path" do
    render_dialog
    assert_selector "[data-admin--new-record-target=url]", text: "Not listed on any page yet", visible: :all

    journal = create_page(title: "Journal")
    ContentBlock.create!(owner: journal, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    render_dialog
    assert_selector "input[value=blog][data-path='/journal']", visible: :all
  end

  test "the form alone keeps the typed title and type and shows the summary" do
    post_record = Post.new
    post_record.errors.add(:title, "can't be blank")
    as(users(:one), channel: :admin) do
      render_inline(Admin::EditorScreen::NewPostFormComponent.new(content_type: "now_update", title: "Typed", errors: post_record.errors))
    end
    assert_selector ".admin-error-summary", text: "1 thing needs fixing"
    assert_selector "input[value=now_update][checked]"
    assert_selector "input#new-post-title[value=Typed][aria-invalid=true]"
  end
end
