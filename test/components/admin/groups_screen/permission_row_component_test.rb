require "test_helper"

# One of the editor's eleven rows (Task 10): checkbox, short label, key in
# mono, scope chips, Edit scope, and the row's own scope editor. The posted
# names are the ones `Admin::GroupsController#grants_from` has always read.
class Admin::GroupsScreen::PermissionRowComponentTest < ViewComponent::TestCase
  include ContentHelper

  def row(key, scope: nil, tree: nil, open: false)
    render_inline Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch(key), scope: scope, tree: tree || tree_for([]), open: open)
  end

  def tree_for(pages, readable: nil, context_only: [])
    readable ||= pages.map(&:id)
    Admin::GroupsScreen::BranchTree.new(pages: pages, readable: readable.to_set, context_only: context_only.to_set, locale: "en")
  end

  test "an unticked row: short label, the key in mono with itself as title, no chips, Edit scope held back" do
    row("posts.delete")

    assert_selector "[data-permission='posts.delete']"
    assert_selector "label", text: "Move to trash"
    assert_selector "code[title='posts.delete']", text: "posts.delete"
    assert_selector "input[type=checkbox][name='group[grants][posts.delete][enabled]'][value='1']:not([checked])[aria-label='Delete posts']"
    assert_no_selector "[data-chips] > *"
    assert_selector "button[aria-expanded='false'][aria-controls]", text: "Edit scope", visible: :all
    assert_selector "button[hidden]", text: "Edit scope", visible: :all
  end

  test "the short labels are presentation only" do
    { "posts.read" => "Read", "posts.create" => "Create", "pages.edit" => "Edit", "pages.publish" => "Publish", "pages.move" => "Move", "pages.delete" => "Move to trash" }.each do |key, label|
      row(key)
      assert_selector "label > span:first-child", text: label, exact_text: true
    end
    assert_equal "Delete posts", AccessControl::Permissions.fetch("posts.delete").label
  end

  test "a ticked posts row with no scope says All content types" do
    row("posts.read", scope: {})

    assert_selector "[data-chips]", text: "All content types"
    assert_selector "input[name='group[grants][posts.read][enabled]'][checked]"
    assert_selector "button:not([hidden])", text: "Edit scope"
  end

  test "a mixed scope: a chip with the type dot per chosen type, Own only, and the editor's inputs keep their names" do
    row("posts.edit", scope: { "content_types" => %w[blog now_update], "own" => true })

    assert_selector "[data-chips] .admin-scope-chip", text: "Blog"
    assert_selector "[data-chips] .admin-scope-chip", text: "Now update"
    assert_selector "[data-chips] .admin-scope-chip", text: "Own only"
    assert_no_selector "[data-chips]", text: "All content types"
    assert_selector "[data-chips] .admin-scope-chip span[aria-hidden]"
    assert_selector "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value=blog][checked]"
    assert_selector "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value=now_update][checked]"
    assert_selector "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value=resume_entry]:not([checked])"
    assert_selector "input[type=checkbox][name='group[grants][posts.edit][own]'][value='1'][checked]"
    assert_text "Only posts the user wrote."
  end

  test "own only with no type shows just Own only" do
    row("posts.edit", scope: { "own" => true })

    assert_selector "[data-chips] .admin-scope-chip", text: "Own only"
    assert_no_selector "[data-chips]", text: "All content types"
  end

  test "more than three chips collapse to +N" do
    row("posts.edit", scope: { "content_types" => %w[blog now_update resume_entry], "own" => true })

    assert_selector "[data-chips] .admin-scope-chip", count: 4 # three, and +1
    assert_selector "[data-chips] .admin-scope-chip", text: "+1"
  end

  test "a removed content type is a warn chip with words and Remove, carried as a tracked hidden input" do
    row("posts.edit", scope: { "content_types" => %w[blog retired_type] })

    assert_selector "[data-removed-type='retired_type']", text: "! retired_type · this type no longer exists"
    assert_selector "[data-removed-type='retired_type'] button[type=button]", text: "Remove"
    assert_selector "input[type=hidden][name='group[grants][posts.edit][content_types][]'][value=retired_type][data-save-bar-track]", visible: :all
    assert_selector "[data-chips]", text: "! retired_type · type removed"
    assert_no_selector "[class*=danger]"
  end

  test "pages: the tree, tri-state, server-rendered" do
    home = create_page(title: "Home x")
    about = create_page(title: "About", parent: home)
    team = create_page(title: "Team", parent: about)
    contact = create_page(title: "Contact", parent: home)
    pages = [ home, about, team, contact ]

    row("pages.edit", scope: { "page_ids" => [ about.id ] }, tree: tree_for(pages))

    assert_selector "[data-chips]", text: "Under About"
    # Chosen: ticked, enabled.
    assert_selector "input[name='group[grants][pages.edit][page_ids][]'][value='#{about.id}'][checked]:not([disabled])"
    # Included by a chosen ancestor: greyed tick, disabled (so never submitted).
    assert_selector "input[name='group[grants][pages.edit][page_ids][]'][value='#{team.id}'][checked][disabled]"
    # An ancestor of a chosen page: partial -- unchecked (so never submitted), marked for the script.
    assert_selector "input[name='group[grants][pages.edit][page_ids][]'][value='#{home.id}']:not([checked]):not([disabled])[data-partial]"
    assert_selector "input[name='group[grants][pages.edit][page_ids][]'][value='#{contact.id}']:not([checked]):not([disabled]):not([data-partial])"
    assert_selector "li[data-chosen='1']", count: 1
  end

  test "an unreadable stored root is a hidden input and a line, with no title and no place in the tree" do
    secret = create_page(title: "Secret area")
    open_page = create_page(title: "Open area")

    row("pages.edit", scope: { "page_ids" => [ secret.id ] }, tree: tree_for([ open_page ], readable: [ open_page.id ]))

    assert_selector "input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{secret.id}']", visible: :all
    assert_text "A page you can't open (kept)"
    assert_selector "[data-chips]", text: "A page you can't open"
    assert_not_includes rendered_content, "Secret area"
    assert_no_selector "li", text: "Secret area"
  end

  test "a context-only ancestor has no box; a chosen one still passes its state down" do
    top = create_page(title: "Hidden top")
    child = create_page(title: "Readable child", parent: top)

    row("pages.edit", scope: { "page_ids" => [ top.id ] }, tree: tree_for([ top, child ], readable: [ child.id ], context_only: [ top.id ]))

    assert_no_selector "input[type=checkbox][value='#{top.id}']"
    assert_selector "input[type=hidden][value='#{top.id}']", visible: :all
    assert_selector "input[type=checkbox][value='#{child.id}'][checked][disabled]"
  end

  test "ids are unique per row, so the scope controls of two rows never share a label" do
    a = render_inline(Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("posts.read"), scope: {}, tree: tree_for([])))
    ids = a.css("[id]").map { |node| node["id"] }
    assert_equal ids.uniq, ids
    assert(ids.all? { |id| id.include?("posts-read") })
  end
end
