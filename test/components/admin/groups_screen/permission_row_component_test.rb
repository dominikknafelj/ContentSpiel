require "test_helper"

# One of the editor's eleven rows: checkbox, short label, key in mono, scope
# chips, Edit scope, and the row's own scope editor. The posted names are the
# ones `Admin::GroupsController#grants_from` reads.
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
    assert_selector "input[type=checkbox][name='group[grants][posts.delete][enabled]'][value='1']:not([checked])[aria-label='Move to trash: Delete posts']"
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

  # Label in name: the accessible name contains the words the row shows.
  test "the checkbox's accessible name contains the visible label" do
    { "posts.read" => "Read posts", "pages.move" => "Move pages", "pages.delete" => "Move to trash: Delete pages" }.each do |key, name|
      row(key)
      assert_selector "[data-permission='#{key}'] input[type=checkbox][aria-label='#{name}']"
    end
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

  test "only a removed type left means the chips say all content types, then the warn chip" do
    row("posts.edit", scope: { "content_types" => %w[retired_type] })

    chips = page.all("[data-chips] .admin-scope-chip").map(&:text)
    assert_equal [ "All content types", "! retired_type · type removed" ], chips
  end

  test "a chosen root below another chosen root is carried as a hidden input beside its disabled box" do
    home = create_page(title: "Home y")
    about = create_page(title: "About", parent: home)
    team = create_page(title: "Team", parent: about)

    row("pages.edit", scope: { "page_ids" => [ about.id, team.id ] }, tree: tree_for([ home, about, team ]))

    assert_selector "input[type=checkbox][value='#{team.id}'][checked][disabled]"
    assert_selector "input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{team.id}']:not([disabled])", visible: :all
    # A chosen root that is not implied has one too, but off: its own box submits it, never both.
    assert_selector "input[type=hidden][value='#{about.id}'][disabled]", visible: :all
    assert_selector "input[type=hidden][value='#{about.id}']:not([disabled])", count: 0, visible: :all
    assert_selector "[data-chips] .admin-scope-chip", count: 1, text: "Under About"
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

  test "a scope chip is a badge, a type's with its dot as the mark, a removed type's warn" do
    row("posts.edit", scope: { "content_types" => %w[blog retired_type], "own" => true })

    neutral = [ Admin::Ui::BadgeComponent::CLASS, Admin::Ui::BadgeComponent::TONES.fetch(:neutral), "admin-scope-chip" ].join(" ")
    warn = [ Admin::Ui::BadgeComponent::CLASS, Admin::Ui::BadgeComponent::TONES.fetch(:warn), "admin-scope-chip" ].join(" ")
    blog = page.find("[data-chips] > span", text: "Blog")
    assert_equal neutral, blog[:class]
    assert_selector "[data-chips] > span[class='#{neutral}'] > span.inline-flex[aria-hidden=true] > span.h-\\[7px\\].w-\\[7px\\].rounded-full", count: 1, visible: :all
    assert_equal neutral, page.find("[data-chips] > span", text: "Own only")[:class]
    assert_empty page.find("[data-chips] > span", text: "Own only").all("[aria-hidden]", visible: :all)
    assert_equal warn, page.find("[data-chips] > span", text: "! retired_type · type removed")[:class]

    row("pages.edit", scope: {})
    assert_equal "admin-scope-chip text-small text-dim", page.find("[data-chips] > span", text: "All pages")[:class]

    # The script redraws the chips after every change, with these strings.
    assert_equal({ neutral_chip: neutral, warn_chip: warn, all_chip: "admin-scope-chip text-small text-dim", mark: Admin::Ui::BadgeComponent::MARK_CLASS, dot: "h-[7px] w-[7px] shrink-0 rounded-full" },
      Admin::GroupsScreen::PermissionRowComponent.chip_classes)
  end

  test "a locked tick has no opacity class and its note is meta" do
    locked_row("posts.edit", { "content_types" => %w[blog] })

    box = page.find("input[type=checkbox][name='group[grants][posts.edit][enabled]'][disabled]")
    assert_equal "cs-checkbox", box[:class]
    # The label follows the box, so the disabled look's `+ label` reaches it.
    assert_selector "input.cs-checkbox[disabled] + label[for='#{box[:id]}']"
    assert_selector "label .admin-locked-note.text-small.text-meta", text: "You can't grant this"
    assert_no_selector "[class*=opacity]"
    assert_no_selector "label span.text-dim"
    assert_no_selector "[class='']"
  end

  test "the scope toggle is a small tertiary button whose words the script reads from its data" do
    row("posts.read", scope: {})

    button = page.find("button[aria-controls='scope-editor-posts-read']")
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small), button[:class]
    assert_equal [ "Done", "Edit scope" ], [ button["data-open-label"], button["data-closed-label"] ]
  end

  def locked_row(key, scope, tree: nil)
    render_inline Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch(key), scope: scope, tree: tree || tree_for([]), locked: true)
  end

  test "a locked row: greyed disabled tick, the note, the chips, no Edit scope and no editor -- and the grant carried by hidden inputs" do
    locked_row("posts.edit", { "content_types" => %w[blog retired_type], "own" => true })

    assert_selector "[data-permission='posts.edit'][data-locked]"
    assert_selector "input[type=checkbox][name='group[grants][posts.edit][enabled]'][checked][disabled]"
    assert_selector ".admin-locked-note", text: "You can't grant this"
    assert_selector "[data-chips] .admin-scope-chip", text: "Blog"
    assert_no_selector "button", visible: :all
    assert_no_selector "[data-scope-editor]", visible: :all
    assert_selector "input[type=hidden][name='group[grants][posts.edit][enabled]'][value='1']", visible: :all
    assert_selector "input[type=hidden][name='group[grants][posts.edit][content_types][]'][value=blog]", visible: :all
    assert_selector "input[type=hidden][name='group[grants][posts.edit][content_types][]'][value=retired_type]", visible: :all
    assert_selector "input[type=hidden][name='group[grants][posts.edit][own]'][value='1']", visible: :all
  end

  test "a locked pages row carries every stored root as it is, an unreadable one and a redundant one included" do
    a = create_page(title: "Branch A")
    a1 = create_page(title: "Leaf", parent: a)
    locked_row("pages.edit", { "page_ids" => [ a.id, a1.id, 999_999 ] }, tree: tree_for([ a, a1 ]))

    [ a.id, a1.id, 999_999 ].each do |id|
      assert_selector "input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{id}']", visible: :all
    end
    assert_no_selector "input[type=checkbox][name$='[page_ids][]']", visible: :all
  end

  test "a locked row that isn't ticked is just an unticked row" do
    render_inline Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("posts.edit"), scope: nil, tree: tree_for([]), locked: true)

    assert_no_selector "[data-locked]"
    assert_selector "button", text: "Edit scope", visible: :all
  end

  test "view-only: the scope toggle is a link (a disabled fieldset leaves it alone), not a button, and the editor is still there to read" do
    render_inline Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("posts.edit"), scope: { "content_types" => [ "blog" ] }, tree: tree_for([]), view_only: true)

    assert_selector "a[role=button][aria-controls='scope-editor-posts-edit'][aria-expanded='false']", text: "View scope", visible: :all
    assert_no_selector "button", visible: :all
    assert_selector "[data-scope-editor] input[type=checkbox][value=blog][checked]", visible: :all
  end
end
