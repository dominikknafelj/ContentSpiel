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

  # The nth code figure of the page, as a script's expression.
  def figure_js(index = 0) = "document.querySelectorAll('#{FIGURE}')[#{index}]"

  # A page with no code figure is not connected: `[].every` is true of anything.
  CONNECTED = "(() => { const figures = Array.from(document.querySelectorAll('#{FIGURE}')); return Boolean(window.Stimulus) && figures.length > 0 && figures.every((figure) => window.Stimulus.getControllerForElementAndIdentifier(figure, 'code-copy')) })()".freeze

  def await_connected = await_js(CONNECTED)

  # Every figure of the page: the script is taken off each, and put back on each.
  def disconnect
    page.execute_script("document.querySelectorAll('#{FIGURE}').forEach((figure) => figure.removeAttribute('data-controller'))")
    await_js("Array.from(document.querySelectorAll('#{FIGURE}')).every((figure) => !window.Stimulus.getControllerForElementAndIdentifier(figure, 'code-copy'))")
  end

  def reconnect
    disconnect
    page.execute_script("document.querySelectorAll('#{FIGURE}').forEach((figure) => figure.setAttribute('data-controller', 'code-copy'))")
    await_connected
  end

  def clipboard(script) = page.execute_script("Object.defineProperty(navigator, 'clipboard', { configurable: true, value: #{script} })")

  RECORDING = "{ writeText: (text) => { (window.__copies ||= []).push(text); window.__copied = text; return Promise.resolve() } }".freeze

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots = page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")

  # The clipboard a test put in is the page's own property; the browser is
  # shared with the tests that follow, so it is taken back.
  teardown { page.execute_script("delete navigator.clipboard; delete window.__copied; delete window.__copies; delete window.__answer") }

  def restore_after(milliseconds) = page.execute_script("document.querySelectorAll('#{FIGURE}').forEach((figure) => figure.setAttribute('data-code-copy-restore-value', '#{milliseconds}'))")

  def status_text(index = 0) = page.evaluate_script("#{figure_js(index)}.querySelector('[role=status]').textContent")

  # [the button's word, the status line, the button hidden?, the strip hidden?]
  def state(index = 0)
    page.evaluate_script("(() => { const figure = #{figure_js(index)}; const button = figure.querySelector('button'); return [button.textContent, figure.querySelector('[role=status]').textContent, button.hidden, figure.querySelector('.code-head').hidden] })()")
  end

  def with_theme(theme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  test "the helper that waits for the script does not take a page with no code figure for connected" do
    visit PublicSite::Urls.new.path_for(@page, "en")
    await_js("Boolean(window.Stimulus)")

    assert_no_selector FIGURE
    assert_equal false, page.evaluate_script(CONNECTED)
  end

  test "the button is shown where there is a clipboard; a press copies the code exactly as stored and says Copied, and the words go back" do
    add_code(CODE, settings: { "language" => "ruby", "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard(RECORDING)
    reconnect
    restore_after(60_000)

    assert_selector "#{FIGURE} .code-head:not([data-code-copy-target])", text: "greet.rb"
    button = find("#{FIGURE} button", text: "Copy")
    button.click

    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Copied", visible: :all
    assert_equal CODE, page.evaluate_script("window.__copied"), "what is copied is the stored code: no markup, the indentation and the line breaks as typed"

    # Design answer C2: the status line is emptied when the word goes back,
    # so the next press writes it again and is announced again.
    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", status_text
    restore_after(60_000)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} [role=status]", exact_text: "Copied", visible: :all
    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", status_text

    # What the script wrote into the page is taken back when it disconnects
    # (Turbo's snapshot would keep it): the button's own word, an empty
    # status, and the button hidden as the server drew it.
    restore_after(60_000)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    disconnect
    assert_selector "#{FIGURE} button[hidden]", exact_text: "Copy", visible: :all
    assert_equal "", status_text

    # The word at rest is the server's value, never read back from the page:
    # a copy of the page that kept an answer comes back saying "Copy".
    page.execute_script("#{figure_js}.querySelector('button').textContent = 'Copied'")
    reconnect
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copy"
  end

  # White space is the content (review focus 4), and so is everything that
  # looks like markup: what reaches the clipboard is the stored string,
  # character for character, with no line break added or lost at its end.
  test "what is copied is the stored code character for character: the first line's indentation, tabs, blank lines and text that looks like markup" do
    source = "\t  <b>first</b> &amp; = 1\n\n    <%= second %>\n\t\n\n  third\t= 3"
    block = add_code(source, settings: { "language" => "erb", "code" => source })
    assert_equal source, block.reload.settings["code"], "the block stores what this test typed"
    open_page
    clipboard(RECORDING)
    reconnect

    find("#{FIGURE} button", text: "Copy").click

    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_equal source, page.evaluate_script("window.__copied")
  end

  # The other way a page is left: by a link. Turbo copies the page a task
  # after it says so (`turbo:before-cache`) and shows that copy again on
  # Back. Whether the script was disconnected before the copy was made is a
  # race, so at the event the script takes back everything it wrote: the
  # words, and `hidden` on the button and on the strip it revealed, so the
  # copy is what the server drew. Turbo also copies a page that is NOT left
  # (a link to an anchor in it), so two tasks later the script puts the
  # button and the strip back, with the focus the button had.
  #
  # The first block has no file name and no language (the strip is the
  # script's), the second has a file name (only the button is).
  test "before Turbo copies the page everything the script wrote is taken back, the strip it revealed included, and on a page that stays it is put back" do
    add_code(CODE, settings: { "code" => CODE })
    add_code(CODE, settings: { "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    restore_after(60_000)
    assert_equal [ "Copy", "", false, false ], state(0)
    find("#{FIGURE} button", match: :first).click
    assert_selector "#{FIGURE} button", exact_text: "Copied"

    # A page that stays: the event, then the two tasks, and the button is
    # back with the focus it had.
    page.execute_script("#{figure_js(0)}.querySelector('button').focus(); document.dispatchEvent(new CustomEvent('turbo:before-cache'))")
    await_js("#{figure_js(0)}.querySelector('button').hidden === false")
    assert_equal [ "Copy", "", false, false ], state(0)
    assert_equal [ "Copy", "", false, false ], state(1)
    assert page.evaluate_script("document.activeElement === #{figure_js(0)}.querySelector('button')"), "the focus the button had is put back with it"

    # In one task: the event, and what the page is at that moment.
    find("#{FIGURE} button", match: :first).click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    in_the_event = page.evaluate_script(<<~JS)
      (() => {
        document.dispatchEvent(new CustomEvent("turbo:before-cache"))
        return Array.from(document.querySelectorAll("#{FIGURE}")).map((figure) => [figure.querySelector("button").textContent, figure.querySelector("[role=status]").textContent, figure.querySelector("button").hidden, figure.querySelector(".code-head").hidden])
      })()
    JS
    assert_equal [ [ "Copy", "", true, true ], [ "Copy", "", true, false ] ], in_the_event
    await_js("#{figure_js(0)}.querySelector('button').hidden === false")

    # Turbo's own copy of a page that stays, made by Turbo's own code: the
    # copy holds what the server drew, and the page has its button back.
    copied = page.evaluate_async_script("const done = arguments[arguments.length - 1]; Turbo.session.view.cacheSnapshot().then((snapshot) => done(snapshot.element.outerHTML))")
    figures = Nokogiri::HTML5(copied).css(FIGURE)
    assert_equal 2, figures.size
    assert figures[0].at_css(".code-head").key?("hidden"), "the strip the script revealed is hidden in Turbo's copy"
    assert_not figures[1].at_css(".code-head").key?("hidden"), "a strip the server drew is in the copy as drawn"
    figures.each do |figure|
      assert figure.at_css("button").key?("hidden"), "the button is hidden in Turbo's copy"
      assert_equal "Copy", figure.at_css("button").text
      assert_equal "", figure.at_css("[role=status]").text
    end
    await_js("#{figure_js(0)}.querySelector('button').hidden === false && #{figure_js(1)}.querySelector('button').hidden === false")
    assert_equal [ "Copy", "", false, false ], state(0)
  end

  test "a page left by a link comes back on Back with the button at rest, and a press there says Copy first and copies" do
    add_code(CODE, settings: { "code" => CODE })
    open_page
    clipboard(RECORDING)
    reconnect
    restore_after(60_000)
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
      assert figure.at_css(".code-head").key?("hidden"), "the copy Turbo kept does not hold a strip the script revealed"
      assert figure.at_css("button").key?("hidden")
    end

    page.go_back
    await_connected
    assert_selector "#{FIGURE} .code-head button", exact_text: "Copy"
    assert_equal "", status_text
    page.execute_script("delete window.__copied")
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_equal CODE, page.evaluate_script("window.__copied")
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
    assert_equal "", status_text
  end

  # Design answer C1. Three blocks: nothing to show, a language, a file name.
  test "without a clipboard a block with nothing to show has no strip and no empty box, one with a name or a language has its strip without a button; with a clipboard each has its button" do
    add_code(CODE, settings: { "code" => CODE })
    add_code(CODE)
    add_code(CODE, settings: { "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("undefined")
    reconnect

    assert_selector "#{FIGURE} pre", text: "def greet(name)", count: 3
    assert_selector "#{FIGURE} .code-head", count: 2
    assert_selector "#{FIGURE} .code-head", text: "RUBY", exact_text: true
    assert_selector "#{FIGURE} .code-head", text: "greet.rb", exact_text: true
    assert_no_selector "#{FIGURE} button"
    assert_equal [ "Copy", "", true, true ], state(0)
    box = page.evaluate_script("(() => { const figure = #{figure_js(0)}; return [figure.getBoundingClientRect().height, figure.querySelector('pre').getBoundingClientRect().height, figure.querySelector('.code-head').getBoundingClientRect().height] })()")
    assert_equal box[0], box[1], "with no strip the figure is its code and nothing else"
    assert_equal 0, box[2]

    clipboard(RECORDING)
    reconnect
    assert_selector "#{FIGURE} .code-head", count: 3
    assert_selector "#{FIGURE} .code-head button", exact_text: "Copy", count: 3
    assert_selector "#{FIGURE} .code-head", exact_text: "Copy", count: 1
    # The button stands in the strip above the code, never over it.
    assert page.evaluate_script("#{figure_js(0)}.querySelector('button').getBoundingClientRect().bottom <= #{figure_js(0)}.querySelector('pre').getBoundingClientRect().top")
  end

  # Design answer C2: "Not copied" is no error the visitor caused, so it has
  # no colour of its own: the three words look the same.
  test "a browser that refuses is told Not copied, in the same colour as Copy and Copied" do
    add_code(CODE)
    open_page
    colour = "getComputedStyle(#{figure_js}.querySelector('button')).color"
    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    # Each colour is read with the pointer where the press left it, on the
    # button, so a hover colour is in all three or in none.
    restore_after(50)
    find("#{FIGURE} button", text: "Copy").click
    await_js("#{figure_js}.querySelector('[role=status]').textContent === ''")
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    at_rest = page.evaluate_script(colour)
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    copied = page.evaluate_script(colour)

    clipboard("{ writeText: () => Promise.reject(new DOMException('refused', 'NotAllowedError')) }")
    reconnect
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click

    assert_selector "#{FIGURE} button", exact_text: "Not copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Not copied", visible: :all
    assert_equal [ at_rest, at_rest ], [ copied, page.evaluate_script(colour) ]

    # A clipboard that throws at once, not by a promise, is a refusal too.
    clipboard("{ writeText: () => { throw new DOMException('refused', 'NotAllowedError') } }")
    reconnect
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click
    assert_selector "#{FIGURE} button", exact_text: "Not copied"
  end

  # Only the clipboard's refusal is "Not copied". A template that lost the
  # `source` target is its author's mistake: an error in the console, and
  # nothing is said to the visitor.
  test "a template without the source target is an error in the console, not a refusal the visitor is told" do
    add_code(CODE)
    open_page
    clipboard(RECORDING)
    reconnect
    restore_after(60_000)
    page.execute_script("#{figure_js}.querySelector('pre').removeAttribute('data-code-copy-target')")

    find("#{FIGURE} button", text: "Copy").click
    expect_js_error(/Missing target element "source" for "code-copy" controller/)
    await_frames

    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", status_text
    assert_nil page.evaluate_script("window.__copied")
  end

  test "two blocks on one page each copy their own code and show their own answer" do
    other = "puts :second"
    add_code(CODE, settings: { "language" => "ruby", "filename" => "one.rb", "code" => CODE })
    add_code(other, settings: { "code" => other })
    open_page
    clipboard(RECORDING)
    reconnect
    restore_after(60_000)

    all("#{FIGURE} button", exact_text: "Copy", count: 2)[1].click
    await_js("#{figure_js(1)}.querySelector('button').textContent === 'Copied'")
    assert_equal [ "Copy", "", false, false ], state(0), "the first block says nothing of the second's press"
    assert_equal [ "Copied", "Copied", false, false ], state(1)
    assert_equal [ other ], page.evaluate_script("window.__copies")

    all("#{FIGURE} button", count: 2)[0].click
    await_js("#{figure_js(0)}.querySelector('button').textContent === 'Copied'")
    assert_equal [ other, CODE ], page.evaluate_script("window.__copies")
  end

  # A phone's width, where a sideways scroll is likeliest, and the second
  # block in a column of a section: what keeps the column from growing with
  # the line is the column's own `min-width: 0` (`sections.css`), and what
  # scrolls the line is the `pre`.
  test "a long line scrolls inside the block and the page never scrolls sideways, at full width and in a column, on a wide window and on a phone's" do
    long = %(x = "#{"a" * 300}")
    add_code(long)
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    add_code(long, section_id: section.id, section_column: 2)
    open_page
    inside = lambda do |width|
      assert_selector "#{FIGURE} pre[tabindex='0']", count: 2
      assert_selector ".content-section__column #{FIGURE}", count: 1
      assert page.evaluate_script("Array.from(document.querySelectorAll('#{FIGURE} pre')).every((pre) => pre.scrollWidth > pre.clientWidth)"), "each block scrolls its own long line (#{width})"
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "the page does not scroll sideways (#{width})"
      assert page.evaluate_script("Array.from(document.querySelectorAll('#{FIGURE}')).every((figure) => figure.getBoundingClientRect().right <= document.documentElement.clientWidth && figure.getBoundingClientRect().width <= figure.parentElement.clientWidth)"), "each block stays inside what holds it (#{width})"
    end

    inside.call("wide")
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.querySelector('#{FIGURE} pre')).overflowX")
    assert page.evaluate_script("#{figure_js(0)}.closest('.content-section') === null && #{figure_js(1)}.clientWidth < #{figure_js(0)}.clientWidth"), "the block in a column is narrower than the one at full width"

    size = page.evaluate_script("[window.innerWidth, window.innerHeight]")
    begin
      page.driver.resize(360, 800)
      await_js("window.innerWidth === 360")
      inside.call("360")
    ensure
      page.driver.resize(*size)
    end
  end

  # Design answer C8, as the browser computes it: the scrollbar's scheme
  # follows the theme and is the opposite one in a strong band, selected
  # code is the accent with its own ink for plain text and for a coloured
  # token alike, and the focus ring is the accent.
  test "the block's scheme follows the theme and a strong band, selected code is the accent pair, and the button's focus ring is the accent" do
    add_code(CODE)
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => "strong" } }).record
    add_code(CODE, section_id: section.id, section_column: 1)
    open_page
    assert_selector ".content-section--strong #{FIGURE}", count: 1
    assert page.evaluate_script("#{figure_js(1)}.closest('.content-section--strong') !== null && #{figure_js(0)}.closest('.content-section') === null")
    probe = lambda do |index|
      page.evaluate_script(<<~JS)
        (() => {
          const figure = #{figure_js(index)}
          const token = (name) => { const span = document.createElement("span"); span.style.color = `var(${name})`; figure.append(span); const colour = getComputedStyle(span).color; span.remove(); return colour }
          const code = figure.querySelector("code")
          const coloured = figure.querySelector("pre span")
          const selection = (element) => [getComputedStyle(element, "::selection").backgroundColor, getComputedStyle(element, "::selection").color]
          return { scheme: getComputedStyle(figure).colorScheme, plain: selection(code), coloured: selection(coloured), pair: [token("--th-accent"), token("--th-on-accent")], accent: token("--th-accent"),
                   rule: getComputedStyle(figure.querySelector(".code-head")).borderBottomWidth, between: getComputedStyle(figure.querySelector("pre")).borderTopWidth }
        })()
      JS
    end

    { "light" => %w[light dark], "dark" => %w[dark light] }.each do |theme, (plain_scheme, band_scheme)|
      with_theme(theme) do
        [ [ 0, plain_scheme ], [ 1, band_scheme ] ].each do |index, scheme|
          seen = probe.call(index)
          assert_equal scheme, seen["scheme"], "#{theme}, block #{index}"
          assert_equal seen["pair"], seen["plain"], "#{theme}, block #{index}: selected plain text"
          assert_equal seen["pair"], seen["coloured"], "#{theme}, block #{index}: a selected token takes the selection's ink, not its own colour"
          assert_not_equal seen["pair"][0], seen["pair"][1]
          assert_equal [ "1px", "0px" ], [ seen["rule"], seen["between"] ], "#{theme}: one 1px line under the strip"
        end
      end
    end

    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    page.execute_script("#{figure_js}.querySelector('pre').focus()")
    find("#{FIGURE} pre", match: :first).send_keys([ :shift, :tab ])
    assert page.evaluate_script("document.activeElement === #{figure_js}.querySelector('button')"), "Shift+Tab from the code reaches the button"
    ring = page.evaluate_script("(() => { const button = #{figure_js}.querySelector('button'); const style = getComputedStyle(button); const span = document.createElement('span'); span.style.color = 'var(--th-accent)'; button.after(span); const accent = getComputedStyle(span).color; span.remove(); return [button.matches(':focus-visible'), style.outlineStyle, style.outlineWidth, style.outlineColor === accent] })()")
    assert_equal [ true, "solid", "2px", true ], ring
  end
end
