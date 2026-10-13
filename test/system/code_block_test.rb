require "application_system_test_case"

# The Code block on the public site, in a browser (code block spec §4): the
# Copy button, and a long line.
#
# The clipboard is the browser's and a headless one may refuse it, so each
# test puts its own in place of `navigator.clipboard`: one that records what
# it was handed, none at all, or one that refuses. The script asks for the
# clipboard when it connects, so after changing it a test takes the
# controller off the figure and puts it back (`reconnect`), which is also
# how a disconnect is seen.
class CodeBlockSystemTest < ApplicationSystemTestCase
  CODE = "def greet(name)\n  puts \"Hello, \#{name}\"\nend".freeze
  FIGURE = "figure.content-block--code".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Docs")
  end

  def add_code(code, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "code", settings: { "language" => "ruby", "code" => code } }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    await_connected
  end

  def await_connected
    await_js("window.Stimulus && Array.from(document.querySelectorAll('#{FIGURE}')).every((figure) => window.Stimulus.getControllerForElementAndIdentifier(figure, 'code-copy'))")
  end

  def disconnect
    page.execute_script("document.querySelector('#{FIGURE}').removeAttribute('data-controller')")
    await_js("!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{FIGURE}'), 'code-copy')")
  end

  def reconnect
    disconnect
    page.execute_script("document.querySelector('#{FIGURE}').setAttribute('data-controller', 'code-copy')")
    await_connected
  end

  def clipboard(script) = page.execute_script("Object.defineProperty(navigator, 'clipboard', { configurable: true, value: #{script} })")

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots = page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")

  # The clipboard a test put in is the page's own property; the browser is
  # shared with the tests that follow, so it is taken back.
  teardown { page.execute_script("delete navigator.clipboard; delete window.__copied; delete window.__answer") }

  def restore_after(milliseconds) = page.execute_script("document.querySelector('#{FIGURE}').setAttribute('data-code-copy-restore-value', '#{milliseconds}')")

  test "the button is shown where there is a clipboard; a press copies the code exactly as stored and says Copied, and the words go back" do
    add_code(CODE, settings: { "language" => "ruby", "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("{ writeText: (text) => { window.__copied = text; return Promise.resolve() } }")
    reconnect
    restore_after(60_000)

    button = find("#{FIGURE} button", text: "Copy")
    button.click

    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Copied", visible: :all
    assert_equal CODE, page.evaluate_script("window.__copied"), "what is copied is the stored code: no markup, the indentation and the line breaks as typed"

    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")

    # What the script wrote into the page is taken back when it disconnects
    # (Turbo's snapshot would keep it): the button's own word, an empty
    # status, and the button hidden as the server drew it.
    restore_after(60_000)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    disconnect
    assert_selector "#{FIGURE} button[hidden]", exact_text: "Copy", visible: :all
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")
  end

  # White space is the content (review focus 4), and so is everything that
  # looks like markup: what reaches the clipboard is the stored string,
  # character for character, with no line break added or lost at its end.
  test "what is copied is the stored code character for character: the first line's indentation, tabs, blank lines and text that looks like markup" do
    source = "\t  <b>first</b> &amp; = 1\n\n    <%= second %>\n\t\n\n  third\t= 3"
    block = add_code(source, settings: { "language" => "erb", "code" => source })
    assert_equal source, block.reload.settings["code"], "the block stores what this test typed"
    open_page
    clipboard("{ writeText: (text) => { window.__copied = text; return Promise.resolve() } }")
    reconnect

    find("#{FIGURE} button", text: "Copy").click

    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_equal source, page.evaluate_script("window.__copied")
  end

  # The other way a page is left: by a link. Turbo copies the page a task
  # after it says so (`turbo:before-cache`) and shows that copy again on
  # Back, where the script connects to it and would take "Copied" for the
  # button's own word. Whether the script was disconnected before the copy
  # was made is a race, so the first half of this test is the event alone,
  # on a page that stays: the words go back at once and the button stays
  # (Turbo copies a page that is not left, too: a link to an anchor in it).
  test "the words are taken back before Turbo copies the page, and a page left by a link comes back on Back with the button at rest" do
    add_code(CODE)
    open_page
    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"

    at_once = page.evaluate_script(<<~JS)
      (() => {
        document.dispatchEvent(new CustomEvent("turbo:before-cache"))
        const figure = document.querySelector("#{FIGURE}")
        return [figure.querySelector("button").textContent, figure.querySelector("[role=status]").textContent, figure.querySelector("button").hidden]
      })()
    JS
    assert_equal [ "Copy", "", false ], at_once

    find("#{FIGURE} button", text: "Copy").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    find("header a", match: :first).click
    assert_no_selector FIGURE

    kept = nil
    assert_eventually(message: "Turbo kept no snapshot of the page that was left") { (kept = turbo_snapshots.grep(/content-block--code/)).any? }
    kept.each do |html|
      figure = Nokogiri::HTML5(html).at_css(FIGURE)
      assert_equal "Copy", figure.at_css("button").text
      assert_equal "", figure.at_css("[role=status]").text
    end

    page.go_back
    await_connected
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")
  end

  # The browser is asked and answers later. A script that was taken off in
  # between has taken its words back already and says nothing after that.
  test "an answer of the clipboard that comes after the script was disconnected writes nothing" do
    add_code(CODE)
    open_page
    clipboard("{ writeText: () => new Promise((resolve) => { window.__answer = resolve }) }")
    reconnect
    restore_after(60_000) # or the words would go back by themselves while the assertion below still looks
    find("#{FIGURE} button", text: "Copy").click
    await_js("typeof window.__answer === 'function'")

    disconnect
    page.execute_script("window.__answer()")
    await_frames

    assert_selector "#{FIGURE} button[hidden]", exact_text: "Copy", visible: :all
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")
  end

  test "without a clipboard the button stays hidden, and a browser that refuses is told Not copied" do
    add_code(CODE)
    open_page
    clipboard("undefined")
    reconnect

    assert_selector "#{FIGURE} button[hidden]", visible: :all
    assert_selector "#{FIGURE} pre", text: "def greet(name)"

    clipboard("{ writeText: () => Promise.reject(new DOMException('refused', 'NotAllowedError')) }")
    reconnect
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click

    assert_selector "#{FIGURE} button", exact_text: "Not copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Not copied", visible: :all
  end

  test "a long line scrolls inside the block and the page never scrolls sideways, at full width and in a column" do
    long = %(x = "#{"a" * 300}")
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    add_code(long)
    add_code(long, section_id: section.id, section_column: 2)
    open_page

    assert_selector "#{FIGURE} pre[tabindex='0']", count: 2
    assert page.evaluate_script("Array.from(document.querySelectorAll('#{FIGURE} pre')).every((pre) => pre.scrollWidth > pre.clientWidth)"), "each block scrolls its own long line"
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "the page does not scroll sideways"
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.querySelector('#{FIGURE} pre')).overflowX")
  end
end
