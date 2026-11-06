# The setup and the helpers the files of test/system/admin/sections_*_test.rb
# share: a page "Landing" with a two-lane section and an image in each lane.
class Admin::SectionsSystemTestCase < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Landing")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @left = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0)
  end

  def open_editor
    visit_editor(@page)
  end

  def tile(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"
  def face(block) = "#{tile(block)} .admin-block-tile__face"
  def panel(block) = "#block-#{block.id}-panel"
  def caption(block) = "block-#{block.id}-caption"

  # Holds the first PATCH this page sends until `window.__releaseSave()`.
  def hold_first_save
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        const method = (options.method || "GET").toUpperCase()
        if (method === "GET") return originalFetch(url, options)
        if (String(url.url || url).includes("/cs-studio/editing/")) return originalFetch(url, options) // a claim or a release is not one of the saves this test holds
        window.__writes.push(String(url.url || url))
        if (window.__writes.length > 1) return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseSave = () => resolve(originalFetch(url, options)) })
      }
    JS
  end

  # Records every write this page sends from now on, and lets it through.
  def count_writes
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        // a claim or a release (`/cs-studio/editing/`) is not one of the writes this counts
        if ((options.method || "GET").toUpperCase() !== "GET" && !String(url.url || url).includes("/cs-studio/editing/")) window.__writes.push(String(url.url || url))
        return originalFetch(url, options)
      }
    JS
  end

  def section_card = "##{ActionView::RecordIdentifier.dom_id(@section)}"
  def layout_button = "#{section_card} button[aria-label='Layout']"

  def focus_is_on(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def blocks_controller = "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~=\"admin--editor--blocks\"]'), 'admin--editor--blocks')"

  # Moves `block`'s element to the end of `target` (a CSS selector of a lane or
  # the list), or to its start, and sends it, as a drop there does.
  def drop_into(block, target, at: :end)
    page.execute_script(<<~JS)
      const controller = #{blocks_controller}
      const item = document.querySelector('[data-block-id="#{block.id}"]:not([data-admin--editor--section-target="panel"])')
      const from = item.parentElement
      const before = controller.snapshot()
      document.querySelector(#{target.to_json}).#{at == :start ? "prepend" : "append"}(item)
      controller.move(item, from, before)
    JS
  end

  # Every write this page sends from now on is answered as `plan` says, by its
  # number: "hold" keeps it until `window.__release[n]()` -- which then lets it
  # through, or answers for it with `window.__release[n]("fail")` -- "fail"
  # answers with an error page at once, and anything past the plan's end goes
  # through. `window.__writes` lists them.
  def script_writes(*plan)
    page.execute_script(<<~JS, plan)
      const plan = arguments[0]
      const originalFetch = window.fetch
      const failure = () => new Response("<h1>Bad gateway</h1>", { status: 502, headers: { "Content-Type": "text/html" } })
      window.__writes = []
      window.__release = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") return originalFetch(url, options)
        if (String(url.url || url).includes("/cs-studio/editing/")) return originalFetch(url, options) // a claim or a release is not one of the writes the plan scripts
        const number = window.__writes.push(String(url.url || url)) - 1
        if (plan[number] === "fail") return Promise.resolve(failure())
        if (plan[number] !== "hold") return originalFetch(url, options)
        return new Promise((resolve) => { window.__release[number] = (how) => resolve(how === "fail" ? failure() : originalFetch(url, options)) })
      }
    JS
  end

  def lane(column, section = @section) = "#section-#{section.id}-lane-#{column}"
  def tiles_in(column, section = @section) = page.all("#{lane(column, section)} > [data-block-id]").map { |tile| tile["data-block-id"].to_i }
  def cards_in_list = page.all("#content-blocks-list > [data-block-id]").map { |card| card["data-block-id"].to_i }

  def assert_order_eventually(expected)
    seen = nil
    assert_eventually(message: -> { "the order never read #{expected.inspect} (last seen #{seen.inspect})" }) do
      seen = yield
      seen == expected
    end
  end

  def centre(selector)
    page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
  end

  # Where a drag onto `selector` is aimed: low in it, never its middle.
  # SortableJS puts an element that comes from another container before or
  # after the one under the pointer by the half the pointer is in, and at the
  # exact middle it does neither.
  def drop_point(selector)
    page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.bottom - 8] })()", selector)
  end

  # Presses on `grip` and walks the pointer to `target` (see `drag_pointer`);
  # the caller waits for the slot it expects and releases.
  def drag_to(grip, target)
    page.execute_script("document.querySelector('#content-blocks-list').scrollIntoView({ block: 'center' })")
    from_x, from_y = centre(grip)
    to_x, to_y = drop_point(target)
    assert_operator [ from_y, to_y ].max, :<, page.evaluate_script("window.innerHeight"), "both ends of the drag are on screen"
    assert_operator [ from_y, to_y ].min, :>, 0, "both ends of the drag are on screen"

    drag_pointer(from_x, from_y, to_y, to_x: to_x)
  end

  def keyboard = page.driver.browser.keyboard
  def menu_button(scope) = "#{scope} button[aria-label='Block actions']"
  def focused_text = page.evaluate_script("document.activeElement?.textContent.trim()")
  def card(block) = "#content-blocks-list > .admin-block-card[data-block-id='#{block.id}']"

  # Opens the block's "⋯" with Enter, walks down to the item and presses Enter
  # on it. Opening puts the focus on the first item that is not disabled.
  def pick_by_keyboard(scope, label)
    page.execute_script("document.querySelector(#{menu_button(scope).to_json}).focus()")
    keyboard.type(:enter)
    assert_selector "#{scope} [role=menu]"
    8.times do
      break if focused_text == label

      keyboard.type(:down)
    end
    assert_equal label, focused_text, "the menu has no item #{label.inspect} the arrow keys reach"
    keyboard.type(:enter)
  end
end
