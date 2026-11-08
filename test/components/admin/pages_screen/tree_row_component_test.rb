require "test_helper"

# One row of the page tree, drawn alone: what a settings save sends back in
# place of the whole tree. It must be the row the tree draws, to the
# attribute, or a save would change how the row looks.
class Admin::PagesScreen::TreeRowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def row_html(fragment, page) = fragment.css("#tree-row-#{page.id}").to_html.gsub(/ nonce="[^"]*"/, "")

  test "a row alone draws what the row draws in the whole tree" do
    with_locales(%w[en de es], default: "en") do
      parent = create_page(title: "Parent", translations: { "de" => { title: "Eltern" } })
      create_page(title: "First child", parent: parent)
      create_page(title: "Second child", parent: parent)
      as(users(:two)) { Notes::Start.call(parent, body: "A note") }
      parent.reload

      alone = render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent, selected: parent, locale: "en", url_options: {}))

      assert_selector "div#tree-row-#{parent.id}.admin-tree-row--selected"
      assert_selector "#tree-row-#{parent.id} [data-translation-marker=missing]", text: "○1"
      assert_selector "#tree-row-#{parent.id} [data-child-count][aria-label='2 subpages']", text: "2"
      assert_selector "#tree-row-#{parent.id} [data-notes-marker]"
      assert_selector "#tree-row-#{parent.id} [data-presence-marker='page-#{parent.id}']", visible: :all
      alone_html = row_html(alone, parent)

      whole = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: parent, locale: "en"))

      assert_equal row_html(whole, parent), alone_html
    end
  end

  test "a row alone costs the same statements for a page with 2 children as with 20" do
    with_locales(%w[en de es], default: "en") do
      parent = create_page(title: "Parent")
      2.times { |index| create_page(title: "Child #{index}", parent: parent) }
      draw = -> { render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent.reload, selected: parent, locale: "en", url_options: {})) }
      draw.call
      small = count_statements { draw.call }

      18.times { |index| create_page(title: "More #{index}", parent: parent) }
      large = count_statements { draw.call }

      assert_selector "#tree-row-#{parent.id} [data-child-count]", text: "20"
      assert_equal small, large
    end
  end

  # A readable page whose parent the viewer can't read is the top of the
  # branch they may read: it is not moved from there (`movable?`), as in the
  # whole tree. Under a branch grant the row alone counts its children through
  # the read scope and the tree counts the children it loaded: the one scoped
  # case in which the two counts could differ, held by the equal markup.
  test "a row under a context-only page has no handle and counts its children, alone as in the tree" do
    branch = create_page(title: "Branch")
    inside = create_page(title: "Inside", parent: branch)
    2.times { |index| create_page(title: "Below #{index}", parent: inside) }
    create_page(title: "Thrown away below", parent: inside).update!(trashed_at: Time.current)
    access_control_groups(:branch_editors).grants.create!(permission: "pages.edit", scope: { "page_ids" => [ inside.id ] })
    access_control_groups(:branch_editors).grants.create!(permission: "pages.move", scope: { "page_ids" => [ inside.id ] })
    Current.actor = users(:editor_branch)

    alone = render_inline(Admin::PagesScreen::TreeRowComponent.for_page(inside.reload, selected: inside, locale: "en", url_options: {}))
    assert_no_selector "#tree-row-#{inside.id} .admin-tree-node__handle", visible: :all
    assert_selector "#tree-row-#{inside.id} [data-child-count]", text: "2", visible: :all
    alone_html = row_html(alone, inside)

    whole = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: inside, locale: "en"))
    assert_selector "li[data-page-id='#{branch.id}'][data-context-only]"
    assert_equal row_html(whole, inside), alone_html
  end

  # The selected look has two writers: the server's drawing here, and
  # `admin--pages--tree#mark`, which moves it in the browser with the marks it
  # is handed (`TreeItemComponent::CLASSES[:row_selected]` and `[:reveal]`)
  # and `aria-current`. So the server's selected row must differ from its
  # unselected one by exactly those, element by element, or the script would
  # leave something of a selection behind, or miss something of one.
  test "a selected row differs from an unselected one by the marks the tree's script moves, and nothing else" do
    with_locales(%w[en de es], default: "en") do
      parent = create_page(title: "Parent")
      create_page(title: "Child", parent: parent)
      other = create_page(title: "Other")
      draw = ->(selected) { render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent.reload, selected: selected, locale: "en", url_options: {})).at_css("#tree-row-#{parent.id}") }
      selected = draw.call(parent)
      unselected = draw.call(other)
      assert selected.at_css("[data-translation-marker]"), "the premise: the row has a translation marker"

      pairs = selected.css("*").to_a.unshift(selected).zip(unselected.css("*").to_a.unshift(unselected))
      assert pairs.all? { |on, off| off && on.name == off.name }, "the two rows are not the same elements"
      row = Admin::Ui::TreeItemComponent::CLASSES
      differences = pairs.filter_map do |on, off|
        on_classes, off_classes = [ on, off ].map { |node| node["class"].to_s.split }
        names = (on.attributes.keys | off.attributes.keys) - %w[class]
        attributes = names.reject { |name| on[name] == off[name] }.sort
        next if on_classes == off_classes && attributes.empty?

        { node: on["id"] || on["data-translation-marker"] || on.name, added: on_classes - off_classes, removed: off_classes - on_classes, attributes: attributes }
      end

      marker = selected.at_css("[data-translation-marker]")["data-translation-marker"]
      assert_equal [
        { node: "tree-row-#{parent.id}", added: [ row[:row_selected] ], removed: [], attributes: [] },
        { node: "tree-link-#{parent.id}", added: [], removed: [], attributes: %w[aria-current] },
        { node: marker, added: [], removed: [ row[:reveal] ], attributes: [] }
      ], differences
      assert_equal "page", selected.at_css("#tree-link-#{parent.id}")["aria-current"]
    end
  end

  # A save's row is drawn alone, under a node the browser keeps: it reads
  # the open set from the cookie the request carried, as the whole tree does.
  test "for_page draws the disclosure from the open cookie handed in, folded or open" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)
    draw = ->(cookie) { render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent.reload, selected: parent, locale: "en", url_options: {}, open_cookie: cookie)) }
    disclosure = "#tree-row-#{parent.id} > button.admin-tree-row__disclosure"

    draw.call(nil)
    assert_selector "#{disclosure}[aria-expanded=false][aria-label='Unfold Parent']"

    draw.call("#{parent.id}")
    assert_selector "#{disclosure}[aria-expanded=true][aria-label='Fold Parent']"

    draw.call("-#{root_page.id}.#{parent.id + 1000}")
    assert_selector "#{disclosure}[aria-expanded=false]"

    whole = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: parent, locale: "en", open_cookie: "#{parent.id}"))
    alone = render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent.reload, selected: parent, locale: "en", url_options: {}, open_cookie: "#{parent.id}"))
    assert_equal row_html(whole, parent), row_html(alone, parent)
  end

  # Pages draws the one row both trees draw: every part of a page's row is
  # the shared row's, in its order, and the row hands it no class of its own.
  test "a row is the shared row: its parts are TreeItemComponent's classes" do
    with_locales(%w[en de], default: "en") do
      parent = create_page(title: "Parent")
      create_page(title: "Child", parent: parent)
      parent.reload
      parts = Admin::Ui::TreeItemComponent::CLASSES

      render_inline(Admin::PagesScreen::TreeRowComponent.for_page(parent, selected: nil, locale: "en", url_options: {}))

      row = page.find("div#tree-row-#{parent.id}")
      assert_equal [ parts[:row] ], row[:class].split
      assert_equal parent.id.to_s, row["data-page-id"]
      assert_equal "row", row["data-admin--pages--tree-target"]
      assert_equal [ parts[:handle], parts[:disclosure], parts[:mark], parts[:title], parts[:trailing], parts[:add] ],
        row.native.element_children.map { |part| part["class"].split.first }
      assert_selector "#tree-row-#{parent.id} > .#{parts[:title]}[title='Parent'] > a#tree-link-#{parent.id}[data-tree-focus][data-turbo-frame=content]", text: "Parent"
      assert_selector "#tree-row-#{parent.id} > button.#{parts[:disclosure]}[aria-controls='tree-children-#{parent.id}'][aria-expanded=false]"
      trailing = page.find("#tree-row-#{parent.id} > .#{parts[:trailing]}", visible: :all)
      assert trailing.find("[data-translation-marker=missing]", visible: :all)[:class].split.include?(parts[:reveal])
      assert_equal [ parts[:count], parts[:reveal] ], trailing.find("[data-child-count]", visible: :all)[:class].split
      assert_equal [ parts[:add] ], page.find("#tree-row-#{parent.id} > a[aria-label='Add a page under Parent']", visible: :all)[:class].split
      own = row.native.element_children.flat_map { |part| part["class"].split } + [ row.native.at_css("#tree-link-#{parent.id}")["class"].to_s ]
      assert_empty own.reject(&:empty?) - parts.values,
        "a row draws its geometry, ground and weight through the tree's classes, not utilities"
    end
  end
end
