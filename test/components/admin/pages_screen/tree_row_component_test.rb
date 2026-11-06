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
  # whole tree.
  test "a row under a context-only page has no handle, alone as in the tree" do
    branch = create_page(title: "Branch")
    inside = create_page(title: "Inside", parent: branch)
    access_control_groups(:branch_editors).grants.create!(permission: "pages.edit", scope: { "page_ids" => [ inside.id ] })
    access_control_groups(:branch_editors).grants.create!(permission: "pages.move", scope: { "page_ids" => [ inside.id ] })
    Current.actor = users(:editor_branch)

    alone = render_inline(Admin::PagesScreen::TreeRowComponent.for_page(inside.reload, selected: inside, locale: "en", url_options: {}))
    assert_no_selector "#tree-row-#{inside.id} .admin-tree-node__handle", visible: :all
    alone_html = row_html(alone, inside)

    whole = render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: inside, locale: "en"))
    assert_selector "li[data-page-id='#{branch.id}'][data-context-only]"
    assert_equal row_html(whole, inside), alone_html
  end
end
