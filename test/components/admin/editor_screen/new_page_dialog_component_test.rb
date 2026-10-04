require "test_helper"

# The New page dialog (design pass round 2, Task 15).
class Admin::EditorScreen::NewPageDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @about = create_page(title: "About")
    @team = create_page(title: "Team", parent: @about)
    @other = create_page(title: "Other")
  end

  def render_dialog(user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPageDialogComponent.new(**options)) }
  end

  test "a 560 wide dialog with Title, Inside, Page type, a URL line and the draft note" do
    render_dialog
    assert_selector "dialog#new-page-dialog[data-dialog-width=form]", visible: :all
    assert_selector "#new-page-dialog-title", text: "New page", visible: :all
    assert_selector "form#new-page-form[action='/cs-studio/pages'][data-turbo-frame='_top'][data-controller='admin--new-record']", visible: :all
    assert_selector "label[for=new-page-title]", text: "Title", visible: :all
    assert_selector "input#new-page-title[name='page[title]'][autofocus]", visible: :all
    assert_selector "select#new-page-inside[name='page[parent_id]']", visible: :all
    assert_selector "label[for=new-page-type]", text: "Page type", visible: :all
    assert_selector "select#new-page-type[name='page[page_type]'] option[value=standard]", text: "Standard", visible: :all
    assert_selector "select#new-page-type option[value=landing]", text: "Landing", visible: :all
    assert_selector "[data-admin--new-record-target=url]", text: "URL: /", visible: :all
    assert_selector "dialog footer button[form=new-page-form]", text: "Create page", visible: :all
    assert_selector "dialog footer button", text: "Cancel", visible: :all
  end

  test "Inside lists every page the owner may create under, indented by depth, in tree order" do
    render_dialog
    options = page.all("#new-page-inside option", visible: :all)
    assert_equal [ root_page.id, @about.id, @team.id, @other.id ].map(&:to_s), options.map { |option| option[:value] }
    assert_equal [ "Home", "  About", "    Team", "  Other" ], options.map(&:text)
  end

  test "each option carries its parent's public path for the URL line" do
    render_dialog
    assert_selector "#new-page-inside option[value='#{@team.id}'][data-path='/about/team'][data-title=Team]", visible: :all
    assert_selector "#new-page-inside option[value='#{root_page.id}'][data-path='']", visible: :all
  end

  test "the preset parent is selected, and the note names it" do
    as(users(:one), channel: :admin) { render_inline(Admin::EditorScreen::NewPageFormComponent.new(parent_id: @about.id)) }
    assert_selector "#new-page-inside option[selected][value='#{@about.id}']"
    assert_selector "[data-admin--new-record-target=note]", text: "Created as a draft at the end of About. Drag it in the tree to move it."
    assert_selector "[data-admin--new-record-target=url]", text: "URL: /about/"
  end

  test "a branch editor sees only their branch, and Home only when allowed" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @about.id ] })
    render_dialog(users(:editor_branch))
    assert_equal [ @about.id, @team.id ].map(&:to_s), page.all("#new-page-inside option", visible: :all).map { |option| option[:value] }
  end

  test "a trashed page is not offered" do
    as_owner { Trash::Move.call(@other) }
    render_dialog
    assert_no_selector "#new-page-inside option[value='#{@other.id}']", visible: :all
  end

  test "nothing renders for a viewer who may create no page" do
    render_dialog(users(:reader))
    assert_no_selector "dialog", visible: :all
  end

  test "the form alone shows the typed values and an error summary linked to the title" do
    page_record = Page.new
    page_record.errors.add(:title, "can't be blank")
    as(users(:one), channel: :admin) do
      render_inline(Admin::EditorScreen::NewPageFormComponent.new(parent_id: @about.id, title: "Typed", page_type: "landing", errors: page_record.errors))
    end
    assert_selector ".admin-error-summary", text: "1 thing needs fixing"
    assert_selector ".admin-error-summary a[href='#new-page-title']", text: "Title can't be blank"
    assert_selector "input#new-page-title[value=Typed][aria-invalid=true]"
    assert_selector "#new-page-type option[selected][value=landing]"
  end
end
