require "application_system_test_case"

# The Table block on the public site, in a browser (table block spec, "The
# public side"): a table wider than the column scrolls inside its own box and
# the page never does, the header column stays put under the scroll and is
# not faded, and a table that fits has no fade. Every test that resizes the
# window puts the size back.
class TableBlockSystemTest < ApplicationSystemTestCase
  BOX = "div.table-scroll".freeze
  WIDE = (1..7).map { |n| "Column #{n}" }.freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Prices")
  end

  def grid(columns, rows: 3)
    head = "| " + columns.join(" | ") + " |\n| " + columns.map { "---" }.join(" | ") + " |\n"
    head + (1..rows).map { |r| "| " + columns.each_index.map { |c| "r#{r}c#{c + 1} cell text" }.join(" | ") + " |" }.join("\n")
  end

  def open_table(columns, header_column: false, caption: nil, background: nil, rows: 3)
    doc = rich_doc(grid(columns, rows: rows), tables: true)
    if header_column
      doc = doc.deep_dup
      rows = doc["content"].find { |node| node["type"] == "table" }["content"]
      rows.drop(1).each { |row| row["content"].first["type"] = "tableHeader" }
    end
    attributes = { block_type: "table" }
    if background
      section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => background } }).record
      attributes.merge!(section_id: section.id, section_column: 1)
    end
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: attributes, translations: { "en" => { body: doc, caption: caption }.compact })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector BOX
  end

  def box(expression) = page.evaluate_script("(() => { const box = document.querySelector('#{BOX}'); return #{expression} })()")

  def with_window(width, height = 800)
    page.driver.resize(width, height)
    yield
  ensure
    page.driver.resize(1400, 1400)
  end

  # The mask's opaque span, as the two lengths the box computes for its ends.
  def fades = box("[getComputedStyle(box).getPropertyValue('--table-fade-start').trim(), getComputedStyle(box).getPropertyValue('--table-fade-end').trim()]")

  test "a table wider than the column scrolls in its own box and the page never scrolls sideways" do
    with_window(375) do
      open_table(WIDE)

      assert_operator box("box.scrollWidth"), :>, box("box.clientWidth"), "the box has more than it shows"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth")
      assert_equal "Column 1", box("box.querySelector('th').textContent.trim()"), "a header is not squeezed into letters"
      assert_operator box("box.querySelector('th').getBoundingClientRect().width"), :>=, 60
    end
  end

  test "scrolled sideways, the header column stays at the same left and is not faded, and the edge fade follows the scroll" do
    with_window(375) do
      open_table(WIDE, header_column: true)
      cell = "box.querySelector('tbody th[scope=row]')"
      left = box("#{cell}.getBoundingClientRect().left")
      assert_equal "0", box("getComputedStyle(#{cell}, '::after').opacity"), "no left fade before any scroll"

      box("box.scrollLeft = 120")
      assert_eventually(message: "the sticky cell's fade comes in") { box("getComputedStyle(#{cell}, '::after').opacity") == "1" }
      assert_in_delta left, box("#{cell}.getBoundingClientRect().left"), 0.5, "the header column did not move"
      assert_equal "0px", fades.first, "the box's mask does not fade the left, where the sticky cell is"
      assert_equal "24px", fades.last, "more to the right: the right edge fades"
      assert_not_equal "rgba(0, 0, 0, 0)", box("getComputedStyle(#{cell}).backgroundColor"), "the sticky cell hides what scrolls under it"

      box("box.scrollLeft = box.scrollWidth")
      assert_eventually(message: "the right fade goes at the end") { fades.last == "0px" }
    end
  end

  test "a table that fits has no fade on either side" do
    open_table([ "Plan", "Price" ])

    assert_not box("box.scrollWidth > box.clientWidth"), "nothing to scroll"
    assert_equal [ "0px", "0px" ], fades
  end

  # A colour as the browser resolves it, from a token on the element itself.
  TOKEN = "const token = (name) => { const span = document.createElement('span'); span.style.color = `var(${name})`; box.append(span); const colour = getComputedStyle(span).color; span.remove(); return colour };".freeze

  def with_scheme(scheme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", scheme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  def drawn
    page.evaluate_script(<<~JS.squish)
      (() => { const box = document.querySelector('#{BOX}'); #{TOKEN}
        const colour = (selector, property = 'color') => getComputedStyle(box.querySelector(selector))[property];
        return { head: [colour('thead th'), token('--th-table-head')], cell: [colour('tbody td'), token('--th-ink')],
                 caption: [colour('caption'), token('--th-table-caption')], dim: token('--th-dim'),
                 rule: [colour('thead th', 'borderBottomColor'), token('--th-table-rule')],
                 ground: [colour('tbody th[scope=row]', 'backgroundColor'), token('--th-table-ground')] } })()
    JS
  end

  # Equal to its token is not enough by itself: a scheme or a band that
  # changed nothing would pass it. So the head's colour must also MOVE where
  # the tokens say it does: between light and dark on the page and in the
  # band, and between the page and the band in light. In dark it does not
  # move between the two, by the tokens' own values (the page's ink and the
  # strong band's text are both #ededee), so that pair is not asserted.
  test "in both schemes the header, cells and caption are drawn in the table's tokens, on the page and in a strong band" do
    heads = {}
    [ nil, "strong" ].each do |background|
      @page.content_blocks.destroy_all
      open_table(%w[Plan Price Notes], header_column: true, caption: "Plans compared", background: background)
      %w[light dark].each do |scheme|
        with_scheme(scheme) do
          seen = drawn
          %w[head cell caption rule ground].each do |part|
            assert_equal seen[part].last, seen[part].first, "#{background || 'plain'} band, #{scheme}: #{part}"
          end
          heads[[ background || "plain", scheme ]] = seen["head"].first
        end
      end
    end

    %w[plain strong].each do |band|
      assert_not_equal heads[[ band, "light" ]], heads[[ band, "dark" ]], "#{band}: the head's colour is the scheme's"
    end
    assert_not_equal heads[%w[plain light]], heads[%w[strong light]], "light: the strong band re-values the head"
  end

  test "in a tinted band the caption is the dim colour, not the page's meta" do
    open_table(%w[Plan Price], header_column: true, caption: "Plans compared", background: "tinted")
    %w[light dark].each do |scheme|
      with_scheme(scheme) do
        seen = drawn
        assert_equal seen["dim"], seen["caption"].first, "tinted band, #{scheme}"
        assert_equal seen["caption"].last, seen["caption"].first
      end
    end
  end

  test "a word longer than a cell's floor breaks inside the cell and the page does not scroll" do
    with_window(375) do
      open_table(%w[Plan Price])
      box("box.querySelector('tbody td').textContent = 'x'.repeat(120); 0")

      assert_operator box("box.querySelector('tbody td').scrollWidth"), :<=, box("box.querySelector('tbody td').clientWidth"), "the word stays in its cell"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth")
    end
  end
end
