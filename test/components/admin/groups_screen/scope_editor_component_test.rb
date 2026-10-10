require "test_helper"

# `Admin::GroupsScreen::ScopeEditorComponent` on its own (round 3, Task 10):
# the scope controls of one permission row. What it must get right is what the
# form SUBMITS as rendered -- "a form saved as rendered changes nothing" -- so
# most assertions here are about which inputs are enabled, ticked or carried.
class Admin::GroupsScreen::ScopeEditorComponentTest < ViewComponent::TestCase
  include ContentHelper

  def editor(key, scope: {}, tree: nil, **options)
    render_inline Admin::GroupsScreen::ScopeEditorComponent.new(permission: AccessControl::Permissions.fetch(key), scope: scope, tree: tree, id: "scope-probe", **options)
  end

  def tree_for(pages, readable: nil, context_only: [])
    readable ||= pages.map(&:id)
    Admin::GroupsScreen::BranchTree.new(pages: pages, readable: readable.to_set, context_only: context_only.to_set, locale: "en")
  end

  def page_box(key, page) = "input[type=checkbox][name='group[grants][#{key}][page_ids][]'][value='#{page.id}']"
  def carried(key, page) = "input[type=hidden][name='group[grants][#{key}][page_ids][]'][value='#{page.id}']"

  # Home > About > Team > Member, the shape the tri-state needs three levels for.
  def family
    about = create_page(title: "About")
    team = create_page(title: "Team", parent: about)
    member = create_page(title: "Member", parent: team)
    [ root_page, about, team, member ]
  end

  test "posts: every registered type as a box, the stored ones ticked, and the Own only switch" do
    editor("posts.edit", scope: { "content_types" => [ "blog" ], "own" => true })

    assert_selector "#scope-probe[data-scope-editor][data-open='false']"
    assert_selector "legend", text: "Content types · none ticked = all"
    AccessControl::Permissions.content_type_choices.each do |name|
      assert_selector "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value='#{name}']"
    end
    assert_selector "input[name='group[grants][posts.edit][content_types][]'][checked]", count: 1
    assert_selector "input[name='group[grants][posts.edit][content_types][]'][value='blog'][checked][data-chip-label='Blog']"
    assert_selector "input[role=switch][name='group[grants][posts.edit][own]'][value='1'][checked]"
    assert_text "Only posts the user wrote."
    assert_no_selector ".admin-branch-picker"
    assert_no_selector "[data-removed-type]"
  end

  test "open: says so, and another form name is used throughout" do
    editor("posts.read", open: true, form_name: "probe[rows]")

    assert_selector "#scope-probe[data-open='true']"
    assert_selector "input[name='probe[rows][posts.read][content_types][]']", minimum: 1
    assert_no_selector "input[name^='group[']", visible: :all
    # Unscoped: nothing ticked, the switch off.
    assert_no_selector "input[checked]"
    assert_selector "input[role=switch][name='probe[rows][posts.read][own]']:not([checked])"
  end

  test "a removed type is a warn chip that carries the name until Remove, tracked so the footer counts the press" do
    editor("posts.edit", scope: { "content_types" => %w[blog retired_type] })

    assert_selector "[data-removed-type='retired_type']", text: "! retired_type · this type no longer exists"
    assert_selector "[data-removed-type='retired_type'] input[type=hidden][name='group[grants][posts.edit][content_types][]'][value='retired_type'][data-save-bar-track]", visible: :all
    assert_selector "[data-removed-type='retired_type'] button[type=button][data-action='click->admin--groups--permission-matrix#removeType']", text: "Remove"
    # It is no box: nothing offers the gone type as a choice.
    assert_no_selector "input[type=checkbox][value='retired_type']"
  end

  test "pages, three levels deep: the chosen page is ticked, everything below it a disabled tick, every ancestor partial" do
    home, about, team, member = family
    editor("pages.edit", scope: { "page_ids" => [ team.id ] }, tree: tree_for([ home, about, team, member ]))

    assert_selector ".admin-branch-picker[data-controller='admin--groups--branch-picker']"
    # Chosen: ticked, enabled, submitted.
    assert_selector "#{page_box("pages.edit", team)}[checked]:not([disabled])"
    assert_selector "li[data-chosen='1']", count: 1
    # Implied: a tick that is disabled, so it is never submitted.
    assert_selector "#{page_box("pages.edit", member)}[checked][disabled]"
    # Partial, at BOTH levels above: unchecked, enabled, marked for the script.
    [ home, about ].each do |ancestor|
      assert_selector "#{page_box("pages.edit", ancestor)}[data-partial]:not([checked]):not([disabled])"
    end
    assert_selector "#{page_box("pages.edit", team)}:not([data-partial])"
    assert_selector "[data-admin--groups--branch-picker-target=note]", text: "contains a chosen page", count: 2
    assert_selector "[data-admin--groups--branch-picker-target=note]", text: "includes 1 subpage", count: 1
    assert_selector "[data-admin--groups--branch-picker-target=note]", text: "included", exact_text: true, count: 1
    # What the form would submit as rendered: exactly the stored root.
    assert_equal [ team.id.to_s ], submitted_page_ids("pages.edit")
    assert_no_text "A page you can't open (kept)"
  end

  test "a root that is chosen AND under another chosen root is carried, so a form saved as rendered keeps both" do
    home, about, team, member = family
    editor("pages.edit", scope: { "page_ids" => [ about.id, team.id ] }, tree: tree_for([ home, about, team, member ]))

    # About: chosen, its box submits it; its carried copy stands aside.
    assert_selector "#{page_box("pages.edit", about)}[checked]:not([disabled])"
    assert_selector "#{carried("pages.edit", about)}[disabled]", visible: :all
    # Team: chosen and implied -- the box is disabled, the hidden input carries it.
    assert_selector "#{page_box("pages.edit", team)}[checked][disabled]"
    assert_selector "#{carried("pages.edit", team)}:not([disabled])", visible: :all
    assert_selector "li[data-chosen='1']", count: 2
    # Member is only implied: nothing carries it.
    assert_no_selector carried("pages.edit", member), visible: :all
    assert_equal [ about.id, team.id ].map(&:to_s).sort, submitted_page_ids("pages.edit").sort
    # A carried root is not tracked: it is no change the footer could count.
    assert_no_selector "#{carried("pages.edit", team)}[data-save-bar-track]", visible: :all
  end

  test "a stored root that is in the trash has no place in the tree: it is carried, with the line and the warning" do
    home, about, team, member = family
    Trash::Move.call(team) # takes Member with it
    tree = Admin::GroupsScreen::BranchTree.for(users(:one), locale: "en")
    editor("pages.edit", scope: { "page_ids" => [ team.id ] }, tree: tree)

    assert_no_selector page_box("pages.edit", team)
    assert_no_selector page_box("pages.edit", member)
    assert_no_text "Team"
    assert_selector "#{carried("pages.edit", team)}[data-admin--groups--branch-picker-target=kept]:not([disabled])", visible: :all
    assert_selector "p", text: "A page you can't open (kept)", count: 1
    assert_selector "p.admin-unreadable-branches", text: "Some of these branches are pages you can't open. Only someone who can open them can change this permission."
    # Nothing above it reads partial: the tree doesn't know where it was.
    assert_no_selector "input[data-partial]"
    assert_selector "#{page_box("pages.edit", about)}:not([checked])"
    assert_equal [ team.id.to_s ], submitted_page_ids("pages.edit")
    assert home.present?
  end

  test "a context-only ancestor is greyed text with no box; chosen, it is carried and its mark is a tick" do
    home, about, team, member = family
    tree = tree_for([ home, about, team, member ], readable: [ team.id, member.id ], context_only: [ home.id, about.id ])

    editor("pages.edit", scope: { "page_ids" => [ team.id ] }, tree: tree)
    assert_no_selector page_box("pages.edit", about)
    assert_selector "span[title=\"You can't open this page\"]", text: "About"
    assert_selector "span[title=\"You can't open this page\"] [data-admin--groups--branch-picker-target=mark]", text: "–", count: 2
    assert_no_text "A page you can't open (kept)"

    editor("pages.edit", scope: { "page_ids" => [ about.id ] }, tree: tree)
    assert_no_selector page_box("pages.edit", about)
    assert_selector "span[title=\"You can't open this page\"]", text: "✓About"
    assert_selector "#{carried("pages.edit", about)}[data-admin--groups--branch-picker-target=kept]", visible: :all
    assert_selector "#{page_box("pages.edit", team)}[checked][disabled]"
    assert_equal [ about.id.to_s ], submitted_page_ids("pages.edit")
  end

  test "an unscoped pages permission: every box unticked, nothing submitted; with no tree there is no branch section" do
    home, about, team, member = family
    editor("pages.move", tree: tree_for([ home, about, team, member ]))
    assert_selector ".admin-branch-picker input[type=checkbox]", count: 4
    assert_no_selector ".admin-branch-picker input[checked]"
    assert_empty submitted_page_ids("pages.move")
    assert_text "Page branches · ticking a page includes everything under it · none = all"

    editor("pages.move", tree: nil)
    assert_no_selector ".admin-branch-picker"
  end

  private

  # What a browser would send for `page_ids[]` from this markup: every enabled
  # hidden input, and every enabled box that is ticked.
  def submitted_page_ids(key)
    page.all("input[name='group[grants][#{key}][page_ids][]']", visible: :all).reject { |input| input[:disabled] }
      .select { |input| input[:type] == "hidden" || input[:checked] }.map { |input| input[:value] }
  end
end
