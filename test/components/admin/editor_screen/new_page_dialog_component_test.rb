require "test_helper"

# The New page dialog's shell and its form (design pass round 2, Task 15).
class Admin::EditorScreen::NewPageDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @about = create_page(title: "About")
    @team = create_page(title: "Team", parent: @about)
    @other = create_page(title: "Other")
  end

  def render_shell(user = users(:one))
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPageDialogComponent.new) }
  end

  def render_form(user = users(:one), **options)
    as(user, channel: :admin) { render_inline(Admin::EditorScreen::NewPageFormComponent.new(**options)) }
  end

  test "the shell is a 560 wide dialog with a loading line, an empty frame and a disabled Create button" do
    render_shell
    assert_selector "dialog#new-page-dialog[data-dialog-width=form]", visible: :all
    assert_selector "#new-page-dialog-title", text: "New page", visible: :all
    assert_selector "[data-controller=admin--new-record][data-admin--new-record-kind-value=page][data-admin--new-record-url-value='/cs-studio/pages/new']", visible: :all
    assert_selector "[data-admin--new-record-target=loading]", text: "Loading…", visible: :all
    assert_selector "[data-admin--new-record-target=failure][hidden] button", text: "Try again", visible: :all
    assert_selector "turbo-frame#new-page-form-frame:empty", visible: :all
    assert_selector "dialog footer button[form=new-page-form][disabled]", text: "Create page", visible: :all
    assert_selector "dialog footer button", text: "Cancel", visible: :all
    assert_no_selector "form#new-page-form", visible: :all
  end

  test "the shell runs no query for pages and renders for a viewer who holds the right anywhere" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/FROM "pages"|public_paths/) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { render_shell }
    assert_empty queries
  end

  test "nothing renders for a viewer who may create no page" do
    render_shell(users(:reader))
    assert_no_selector "dialog", visible: :all
  end

  test "the form: Title, Inside, Page type, a URL line and the draft note, posting to pages" do
    render_form
    assert_selector "form#new-page-form[action='/cs-studio/pages'][data-turbo-frame='_top']"
    assert_selector "label[for=new-page-title]", text: "Title"
    assert_selector "input#new-page-title[name='page[title]'][autofocus]"
    assert_selector "select#new-page-inside[name='page[parent_id]']"
    assert_selector "select#new-page-type[name='page[page_type]'] option[value=standard]", text: "Standard"
    assert_selector "select#new-page-type option[value=landing]", text: "Landing"
    assert_selector "[data-admin--new-record-target=url]", text: "URL: /"
  end

  test "Inside lists every page the owner may create under, indented by depth, in tree order" do
    render_form
    options = page.all("#new-page-inside option")
    assert_equal [ root_page.id, @about.id, @team.id, @other.id ].map(&:to_s), options.map { |option| option[:value] }
    assert_equal [ "Home", "  About", "    Team", "  Other" ], options.map(&:text)
  end

  test "a page with no title in this language reads (untitled), as in the tree" do
    blank = Page.create!(parent: root_page, page_type: :standard, title: "x", slug: "blank-one")
    blank.update_columns(title: {})
    render_form
    assert_selector "#new-page-inside option[value='#{blank.id}']", text: /\(untitled\)/
  end

  test "each option carries its parent's public path for the URL line" do
    render_form
    assert_selector "#new-page-inside option[value='#{@team.id}'][data-path='/about/team'][data-title=Team]"
    assert_selector "#new-page-inside option[value='#{root_page.id}'][data-path='']"
  end

  test "the preset parent is selected, and the note names it" do
    render_form(parent_id: @about.id)
    assert_selector "#new-page-inside option[selected][value='#{@about.id}']"
    assert_selector "[data-admin--new-record-target=note]", text: "Created as a draft at the end of About. Drag it in the tree to move it."
    assert_selector "[data-admin--new-record-target=url]", text: "URL: /about/"
  end

  test "a branch editor is offered the branch root itself, indented from it, and nothing outside" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ @about.id ] })
    render_form(users(:editor_branch))
    options = page.all("#new-page-inside option")
    assert_equal [ @about.id, @team.id ].map(&:to_s), options.map { |option| option[:value] }
    assert_equal [ "About", "  Team" ], options.map(&:text)
  end

  test "a trashed page is not offered" do
    as_owner { Trash::Move.call(@other) }
    render_form
    assert_no_selector "#new-page-inside option[value='#{@other.id}']"
  end

  test "with no page at all there is no Inside, and the note says it creates the home page" do
    [ ContentBlock, PublicPath, PageHierarchy, Page ].each(&:delete_all)
    render_form
    assert_no_selector "#new-page-inside"
    assert_selector "[data-admin--new-record-target=note]", text: "Created as the home page."
    assert_selector "input#new-page-title"
  end

  test "the form builds in a constant number of queries however many pages there are" do
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { render_form }
      queries
    end
    count.call # warm grants and caches
    small = count.call
    25.times { |index| create_page(title: "Many #{index}", parent: @about) }
    assert_equal small, count.call
  end

  test "the form alone shows the typed values and an error summary linked to the title" do
    page_record = Page.new
    page_record.errors.add(:title, "can't be blank")
    render_form(parent_id: @about.id, title: "Typed", page_type: "landing", errors: page_record.errors)
    assert_selector ".admin-error-summary", text: "1 thing needs fixing"
    assert_selector ".admin-error-summary a[href='#new-page-title']", text: "Title can't be blank"
    assert_selector "input#new-page-title[value=Typed][aria-invalid=true]"
    assert_selector "#new-page-type option[selected][value=landing]"
  end

  test "a title with no letter or digit collapses its slug errors into one sentence" do
    result = as_owner { Pages::Save.call(Page.new, attributes: { parent: @about }, translations: { "en" => { title: "!!!" } }) }
    assert_not result.ok?
    render_form(errors: result.record.errors)
    assert_selector ".admin-error-summary", text: "1 thing needs fixing"
    assert_selector ".admin-error-summary", text: "Title needs at least one letter or digit"
  end
end
