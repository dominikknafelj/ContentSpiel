require "application_system_test_case"

# Both trees draw one row (`Admin::Ui::TreeItemComponent`): Pages renders it,
# and the mind graph's list builds the same markup from its `CLASSES`
# (`data-tree-classes`). The guards hold that neither file writes a look of
# its own; only a browser can show that the two rows come out the same, so
# this measures a page's row two levels below Home in each, as drawn, and
# the step from its parent's row.
class Admin::TreeItemParitySystemTest < Admin::MindGraphSystemTestCase
  # What is compared: the row's height, the step between a parent's mark and
  # its child's, the mark's box, the parent's title (size, weight, ink), the
  # selected title's weight, and the selected row's bar and ground. Lengths
  # within half a pixel; the rest exactly.
  MEASURE = <<~JS.freeze
    ((row, parent) => {
      const mark = (element) => element.querySelector(":scope > .admin-tree-row__mark").getBoundingClientRect()
      const title = (element) => getComputedStyle(element.querySelector(":scope > .admin-tree-row__title"))
      const style = getComputedStyle(row)
      return { height: row.getBoundingClientRect().height, step: mark(row).left - mark(parent).left, mark_width: mark(row).width, mark_height: mark(row).height,
               title_size: title(parent).fontSize, title_weight: title(parent).fontWeight, title_color: title(parent).color, selected_weight: title(row).fontWeight,
               shadow: style.boxShadow, background: style.backgroundColor }
    })(document.querySelector(arguments[0]), document.querySelector(arguments[1]))
  JS

  # The keys on which two samples differ.
  def parted(one, other)
    one.keys.reject do |key|
      one[key].is_a?(Numeric) ? (one[key] - other[key]).abs <= 0.5 : one[key] == other[key]
    end
  end

  def measure(row, parent)
    page.driver.browser.mouse.move(x: 0, y: 0) # no row is under the pointer: hover is not the selection's ground
    page.evaluate_script(MEASURE, row, parent)
  end

  def count_width(row)
    page.driver.browser.mouse.move(x: 0, y: 0)
    page.evaluate_script("document.querySelector(arguments[0]).querySelector('.admin-tree-row__count').getBoundingClientRect().width", row)
  end

  test "the Pages tree and the mind graph's list draw one row" do
    section = create_page(title: "Section")
    deep = create_page(title: "Deep", parent: section)

    at_window(1600) do
      visit_editor(deep)
      pages = measure("#tree [data-tree-row][data-tree-id='#{deep.id}']", "#tree [data-tree-row][data-tree-id='#{section.id}']")
      assert_equal %w[height], parted(pages, pages.merge("height" => pages["height"] + 1)), "the comparison cannot tell two heights apart"
      assert_operator pages["step"], :>, 0, "the child's mark does not stand right of its parent's: the rows measured are not a parent and its child"
      # The parent's count rests clipped in Pages, and is shown at rest in
      # the graph's list with a figure's width from the start.
      assert_operator count_width("#tree [data-tree-row][data-tree-id='#{section.id}']"), :<=, 1, "the Pages count at rest is not clipped"

      visit_screen admin_mind_graph_path
      await_graph
      # Section is folded in the list until its page is selected, which
      # opens the path to it.
      row = "#{LIST} [role=treeitem][data-node-id='#{nid(deep)}'] > .admin-tree-row"
      click_node(deep)
      assert_selector "#{row}.admin-tree-row--selected"
      graph = measure(row, "#{LIST} [role=treeitem][data-node-id='#{nid(section)}'] > .admin-tree-row")
      assert_operator count_width("#{LIST} [role=treeitem][data-node-id='#{nid(section)}'] > .admin-tree-row"), :>=, 14, "the graph's count at rest has no figure's width: a cut title's ellipsis would move on hover"

      assert_empty parted(pages, graph), "the trees' rows differ: Pages #{pages.inspect}, the graph's list #{graph.inspect}"
    end
  end
end
