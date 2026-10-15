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
    assert_operator button.evaluate_script("this.getBoundingClientRect().height"), :>=, 28, "Copy's target"
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
  # Back, so at the event the script takes back its WORDS, which no later
  # `connect` could tell from the server's. `hidden` it leaves alone: Turbo
  # also copies a page that is NOT left (a link to an anchor in it), and a
  # strip hidden there, for however short a time, is a jump of everything
  # below it. A copy may therefore hold a button the script revealed; the
  # page shown from it runs `connect`, which decides both `hidden`s again
  # (the last lines here: a copy with everything revealed, in a browser with
  # no clipboard).
  #
  # The first block has no file name and no language (the strip is the
  # script's), the second has a file name (only the button is).
  test "before Turbo copies the page the words are taken back and nothing is hidden, and a page shown from a copy decides again what is shown" do
    add_code(CODE, settings: { "code" => CODE })
    add_code(CODE, settings: { "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    restore_after(60_000)
    assert_equal [ "Copy", "", false, false ], state(0)
    find("#{FIGURE} button", match: :first).click
    assert_selector "#{FIGURE} button", exact_text: "Copied"

    # In one task: the event, and what the page is at that moment.
    in_the_event = page.evaluate_script(<<~JS)
      (() => {
        #{figure_js(0)}.querySelector("button").focus()
        document.dispatchEvent(new CustomEvent("turbo:before-cache"))
        return Array.from(document.querySelectorAll("#{FIGURE}")).map((figure) => [figure.querySelector("button").textContent, figure.querySelector("[role=status]").textContent, figure.querySelector("button").hidden, figure.querySelector(".code-head").hidden])
      })()
    JS
    assert_equal [ [ "Copy", "", false, false ], [ "Copy", "", false, false ] ], in_the_event
    assert page.evaluate_script("document.activeElement === #{figure_js(0)}.querySelector('button')"), "the button keeps the focus it had"

    # A copy that kept what the script revealed, shown where nothing can be
    # copied: `connect` hides the button and the strip again.
    disconnect
    page.execute_script("document.querySelectorAll('#{FIGURE} button, #{FIGURE} .code-head').forEach((element) => { element.hidden = false })")
    clipboard("undefined")
    page.execute_script("document.querySelectorAll('#{FIGURE}').forEach((figure) => figure.setAttribute('data-controller', 'code-copy'))")
    await_connected
    assert_equal [ [ "Copy", "", true, true ], [ "Copy", "", true, false ] ], [ state(0), state(1) ]
  end

  # A PAGE THAT STAYS. Turbo takes a copy of the page it is on when the
  # browser itself goes to an anchor in it (`historyPoppedWithEmptyState`: a
  # link Turbo does not drive, a typed fragment, Back between two anchors).
  # Nothing of a code block may move then: no `hidden` is touched, by the
  # event or after it, and the page ends at the anchor.
  test "when the browser goes to an anchor in a page that stays, Turbo copies the page and no strip or button is touched, and the page ends at the anchor" do
    add_code(CODE, settings: { "code" => CODE })
    add_code(CODE, settings: { "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("{ writeText: () => Promise.resolve() }")
    reconnect
    page.execute_script(<<~JS)
      const main = document.querySelector("main")
      main.insertAdjacentHTML("afterbegin", '<a id="to-foot" href="#foot" data-turbo="false">To the foot</a>')
      main.insertAdjacentHTML("beforeend", '<div style="height: 3000px"></div><h2 id="foot">Foot</h2><div style="height: 3000px"></div>')
      window.__hidden = []
      window.__caches = 0
      window.__count = () => { window.__caches += 1 }
      window.__watch = new MutationObserver((records) => records.forEach((record) => window.__hidden.push(record.target.className || record.target.tagName)))
      document.querySelectorAll("#{FIGURE}").forEach((figure) => window.__watch.observe(figure, { subtree: true, attributes: true, attributeFilter: ["hidden"] }))
      document.addEventListener("turbo:before-cache", window.__count)
    JS
    before = [ state(0), state(1) ]
    assert_equal [ [ "Copy", "", false, false ], [ "Copy", "", false, false ] ], before

    find("#to-foot").click
    await_js("window.__caches > 0 && location.hash === '#foot'")
    await_frames
    await_frames

    assert page.evaluate_script("document.getElementById('to-foot') !== null"), "the page stayed: it was not drawn again"
    assert_equal [], page.evaluate_script("window.__watch.takeRecords().length ? ['pending'] : window.__hidden"), "no element of a code block had its hidden attribute changed"
    assert_equal before, [ state(0), state(1) ]
    assert_in_delta 0, page.evaluate_script("document.getElementById('foot').getBoundingClientRect().top"), 2, "the page ends at the anchor"
  ensure
    page.execute_script("window.__watch?.disconnect(); document.removeEventListener('turbo:before-cache', window.__count); delete window.__watch; delete window.__hidden; delete window.__caches; delete window.__count")
  end

  # A LINK TO AN ANCHOR that Turbo drives is a visit: Turbo 8 fetches the
  # page and draws it again (`locationWithActionIsSamePage` is false), so the
  # script connects to new elements. The strips above the anchor are the
  # script's to reveal, and the page must still end at the anchor: they are
  # revealed before Turbo scrolls, not after.
  #
  # Scroll anchoring is switched off for the test: Chrome keeps what is in
  # view where it is when something above it grows, so with it a strip
  # revealed AFTER the scroll leaves the page at the anchor all the same and
  # this test could not fail (Task 5b's re-review, N3). Without it the order
  # is seen: this was red, 292 pixels off, with the reveal put off by fifty
  # milliseconds. It is switched off for EVERY element, by a stylesheet the
  # document adopts (which a Turbo visit keeps): `overflow-anchor: none` on
  # the root alone left Chrome compensating. Safari has no scroll anchoring,
  # which is who the order is for.
  test "a link to an anchor in the page, which Turbo draws again, ends at the anchor with every strip and button shown" do
    8.times { add_code(CODE, settings: { "code" => CODE }) }
    target = add_code(CODE, settings: { "filename" => "greet.rb", "code" => CODE })
    8.times { add_code(CODE, settings: { "code" => CODE }) }
    open_page
    assert_selector "#{FIGURE} .code-head button", exact_text: "Copy", count: 17
    page.execute_script("const sheet = new CSSStyleSheet(); sheet.replaceSync('* { overflow-anchor: none !important }'); document.adoptedStyleSheets = [sheet]")
    page.execute_script(%(document.querySelector("main").insertAdjacentHTML("afterbegin", '<a id="to-file" href="#code-#{target.id}-file">To the file</a>')))

    find("#to-file").click
    # wait: the link goes when Turbo has fetched and drawn the page again, seventeen blocks of it.
    assert_no_selector "#to-file", wait: 8
    await_connected
    await_js("location.hash === '#code-#{target.id}-file'")
    await_frames

    assert_selector "#{FIGURE} .code-head button", exact_text: "Copy", count: 17
    assert_in_delta 0, page.evaluate_script("document.getElementById('code-#{target.id}-file').getBoundingClientRect().top"), 2, "the page ends at the anchor, with the strips above it already there"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.getElementById('code-#{target.id}-file')).overflowAnchor"), "and the browser did not hold it there: anchoring was still off after the visit"
  ensure
    page.execute_script("document.adoptedStyleSheets = []")
  end

  # Final review M7. A theme's mistyped key is "" outside development, and
  # an attribute that is there and empty is still a value: the word the
  # template wrote on the button is what it goes back to, not nothing.
  test "an empty label keeps the word the template wrote on the button: after an answer the button says it again" do
    add_code(CODE, settings: { "code" => CODE })
    open_page
    clipboard(RECORDING)
    disconnect
    page.execute_script("#{figure_js}.setAttribute('data-code-copy-label-value', ''); #{figure_js}.querySelector('button').textContent = 'Take it'; #{figure_js}.setAttribute('data-controller', 'code-copy')")
    await_connected
    assert_selector "#{FIGURE} button", exact_text: "Take it"

    restore_after(60_000)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Take it"
    assert_equal "", status_text
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
    # wait: the figure goes when Turbo has fetched and drawn the page the link leads to.
    assert_no_selector FIGURE, wait: 8

    kept = nil
    assert_eventually(message: "Turbo kept no snapshot of the page that was left") { (kept = turbo_snapshots.grep(/content-block--code/)).any? }
    kept.each do |html|
      figure = Nokogiri::HTML5(html).at_css(FIGURE)
      assert_equal "Copy", figure.at_css("button").text
      assert_equal "", figure.at_css("[role=status]").text
    end

    # Whether the copy holds the strip shown or hidden is a race between the
    # script's disconnect and Turbo's clone, and does not matter: the page
    # shown from it connects, and has its strip and its button.
    page.go_back
    await_connected
    assert_selector "#{FIGURE} .code-head button", exact_text: "Copy"
    assert_equal [ "Copy", "", false, false ], state
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
  # block in a column of a section. The `pre` scrolls the line. At full width
  # the figure is a block and as wide as what holds it; in a column what
  # holds it is a grid item, which would by itself be as wide as its longest
  # line, a scrolling `pre` included, and what keeps it narrow there is the
  # tracks' `minmax(0, …)` and the column's `min-width: 0` in `sections.css`
  # (`code.css`, "A LONG LINE").
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
  # follows the theme and is dark in a strong band in both schemes (D2), selected
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

    { "light" => %w[light dark], "dark" => %w[dark dark] }.each do |theme, (plain_scheme, band_scheme)|
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

  # THE THEMING CONTRACT, in a browser (code block spec §5,
  # docs/reference/theming.md, "The Code block"). The third theme's template
  # is written from the reference's tables alone: another element, other
  # classes, the documented markup. That the button works under it is what
  # makes the table a promise.
  test "under a theme's own template the Copy button is shown, copies the stored code and says so, with nothing but the documented markup" do
    code = "\tdef a\n\n    \"<b>\" # note\nend"
    add_code(code, settings: { "language" => "ruby", "filename" => "a.rb", "code" => code })
    add_code("plain words", settings: { "code" => "plain words" })
    publish_changes(@page)
    theme_figure = ->(index) { "document.querySelectorAll('div.plain-code')[#{index}]" }

    with_code_theme do
      visit PublicSite::Urls.new.path_for(@page, "en")
      assert_no_selector FIGURE
      assert_selector "div.plain-code", count: 2
      connected = "Array.from(document.querySelectorAll('div.plain-code')).every((block) => window.Stimulus?.getControllerForElementAndIdentifier(block, 'code-copy'))"
      await_js(connected)
      clipboard(RECORDING)
      page.execute_script("document.querySelectorAll('div.plain-code').forEach((block) => block.removeAttribute('data-controller'))")
      await_js("Array.from(document.querySelectorAll('div.plain-code')).every((block) => !window.Stimulus.getControllerForElementAndIdentifier(block, 'code-copy'))")
      assert_equal [ true, true ], page.evaluate_script("Array.from(document.querySelectorAll('div.plain-code button')).map((button) => button.hidden)"), "taken off, the script leaves the buttons as the template wrote them"
      assert_equal [ false, true ], page.evaluate_script("Array.from(document.querySelectorAll('div.plain-code .plain-code__bar')).map((bar) => bar.hidden)"), "a bar with a file name is drawn; one with nothing to read is the script's to show"
      page.execute_script("document.querySelectorAll('div.plain-code').forEach((block) => { block.setAttribute('data-controller', 'code-copy'); block.setAttribute('data-code-copy-restore-value', '60000') })")
      await_js(connected)

      assert_equal [ false, false ], page.evaluate_script("Array.from(document.querySelectorAll('div.plain-code .plain-code__bar')).map((bar) => bar.hidden)"), "the strip target is shown with its button"
      find("div.plain-code:nth-of-type(1) button", exact_text: "Copy").click
      assert_selector "div.plain-code button", exact_text: "Copied", count: 1
      assert_equal "Copied", page.evaluate_script("#{theme_figure.(0)}.querySelector('[role=status]').textContent")
      assert_equal code, page.evaluate_script("window.__copied"), "the stored code to the character: the tab, the blank line, the indentation, and markup as text"
      find("div.plain-code button", exact_text: "Copy").click
      assert_equal [ code, "plain words" ], page.evaluate_script("window.__copies")
      assert_equal "Copy code", page.evaluate_script("#{theme_figure.(1)}.querySelector('button').getAttribute('aria-label')")
    end
  end

  # A theme re-colours code by declaring the seven tokens again, and by
  # nothing else. The suite's stylesheet is the default theme's, so the
  # third theme's stylesheet is put into the page as text AFTER the built
  # one, which is where the build puts a theme's (`ThemeCss.write_entry`:
  # the default's import first, then the theme's). In a strong band the
  # band's own values are nearer the code than a theme's on the root, and
  # the code stays one colour (decision 8).
  test "a theme's stylesheet that declares the seven tokens again re-colours the code in both schemes, and in a strong band the code stays the band's one colour" do
    erb = "<%# note %>\n<p class=\"a\"><% if @x %><%= 1 %><% end %></p>"
    ruby = "# note\ndef a = \"b\""
    add_code(erb, settings: { "language" => "erb", "code" => erb })
    add_code(ruby)
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => "strong" } }).record
    add_code(ruby, section_id: section.id, section_column: 1)
    open_page
    assert page.evaluate_script("#{figure_js(2)}.closest('.content-section--strong') !== null")

    css = ThemeTestHelper::CODE.join("assets/stylesheets/theme.css").read
    theirs = { "light" => css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], "dark" => css[/^\[data-theme="dark"\]\s*\{(.*?)\}/m, 1] }
      .transform_values { |block| block.scan(/--th-syn-(\w+):\s*(#\h{6});/).to_h }
    assert_equal [ CodeHighlight::ROLES, CodeHighlight::ROLES ], theirs.values.map(&:keys)
    # { role => [the span's colour, the theme's value as the browser computes it] } for the blocks on the page,
    # and for the one in the band [its colour, the band's ink, the band's dim].
    seen = lambda do |theme|
      page.evaluate_script(<<~JS, theirs.fetch(theme))
        (() => {
          const values = arguments[0]
          const computed = (element, colour) => { const span = document.createElement("span"); span.style.color = colour; element.append(span); const answer = getComputedStyle(span).color; span.remove(); return answer }
          const figures = Array.from(document.querySelectorAll("#{FIGURE}"))
          const onPage = {}
          figures.slice(0, 2).forEach((figure) => figure.querySelectorAll("pre span").forEach((span) => {
            const role = span.className.replace("syn-", "")
            onPage[role] = [getComputedStyle(span).color, computed(figure, values[role])]
          }))
          const band = figures[2]
          const inBand = {}
          band.querySelectorAll("pre span").forEach((span) => {
            inBand[span.className.replace("syn-", "")] = [getComputedStyle(span).color, computed(band, "var(--th-on-band-strong)"), computed(band, "var(--th-on-band-strong-dim)")]
          })
          return { onPage, inBand }
        })()
      JS
    end

    before = seen.call("light")
    assert_equal CodeHighlight::ROLES.sort, before["onPage"].keys.sort, "the two blocks show all seven roles between them"
    before["onPage"].each { |role, (colour, value)| assert_not_equal value, colour, "#{role} is the default theme's before the theme's stylesheet is there" }

    page.execute_script("const style = document.createElement('style'); style.id = 'third-theme'; style.textContent = arguments[0]; document.head.append(style)", css)
    %w[light dark].each do |theme|
      with_theme(theme) do
        now = seen.call(theme)
        assert_equal CodeHighlight::ROLES.sort, now["onPage"].keys.sort
        now["onPage"].each { |role, (colour, value)| assert_equal value, colour, "#{role} (#{theme}) is the theme's" }
        assert_equal %w[comment keyword string], now["inBand"].keys.sort
        now["inBand"].each do |role, (colour, ink, dim)|
          assert_equal (role == "comment" ? dim : ink), colour, "#{role} in a strong band (#{theme}) is the band's own, whatever the theme declared on the root"
          assert_not_equal ink, dim
        end
      end
    end
  ensure
    page.execute_script("document.getElementById('third-theme')?.remove()")
  end
end
