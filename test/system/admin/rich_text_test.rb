require "application_system_test_case"

# The Tiptap editor in CS Studio (tiptap spec §4.1/§9): `admin--rich-text`
# mounts Tiptap on `Admin::Columns::RichTextColumnComponent`, writes
# `editor.getJSON()` into the column's hidden `…[body]` input and dispatches
# `input` so the form's own `admin--autosave` sends it. Every test here ends
# by reading the *saved* document back and running it through
# `RichText::Document#validate` -- the editor's schema has to match
# `RichText::Schema` exactly (task 7's "schema fidelity" ruling), so anything
# it can produce must be something the server accepts.
#
# Clicks are scripted (`press`), never native, for the reason
# `ApplicationSystemTestCase#press` gives. Typing goes through real CDP key
# events (Cuprite's keyboard) into the focused ProseMirror element (`type_text`),
# since ProseMirror reads its own DOM mutations/`beforeinput` events --
# setting a value from JS would bypass exactly the code under test.
class Admin::RichTextSystemTest < ApplicationSystemTestCase
  YOUTUBE_ID = "dQw4w9WgXcQ".freeze
  # The editor's read-only notice (`admin--rich-text`'s `invalidContent`).
  INVALID_CONTENT = "This text contains something the editor can't show".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @post = create_post(title: "Notes")
  end

  test "typed text with a toolbar Bold autosaves a bold mark" do
    visit_post

    editor.click
    type_text "Hello "
    press "Bold"
    type_text "world"

    document = saved_post_document { |doc| doc_text(doc).include?("world") }
    bold = text_nodes(document).find { |node| node["text"] == "world" }
    assert_equal [ { "type" => "bold" } ], bold["marks"]
    assert_equal "Hello ", text_nodes(document).first["text"]
  end

  test "pasting a YouTube URL inserts a youtube node" do
    visit_post

    editor.click
    paste(text: "https://youtu.be/#{YOUTUBE_ID}")

    assert_selector ".ProseMirror [data-youtube-id='#{YOUTUBE_ID}']"
    document = saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "youtube" } }
    youtube = nodes(document).find { |node| node["type"] == "youtube" }
    assert_equal({ "id" => YOUTUBE_ID }, youtube["attrs"])
  end

  test "an image uploaded through the Image button is inserted and its alt text saved" do
    visit_post

    editor.click
    attach_file(file_fixture("tiny.png").to_s) { press "Image" }

    within(".admin-rich-text-popover") do
      fill_in "Alt text", with: "A"
      press "Done"
    end

    document = saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" && node.dig("attrs", "alt") == "A" } }
    image = nodes(document).find { |node| node["type"] == "image" }
    asset = Media::Asset.find(image.dig("attrs", "asset_id"))
    assert_equal({ "asset_id" => asset.id, "alt" => "A", "caption" => "" }, image["attrs"])
    assert_selector ".ProseMirror img[src='#{asset.url}']"

    # The image is still selected after Done: the Image button now edits it
    # (the keyboard route to alt text) instead of uploading another.
    press "Image"
    within(".admin-rich-text-popover") do
      assert_field "Alt text", with: "A"
      fill_in "Caption", with: "C"
      press "Done"
    end
    saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" && node.dig("attrs", "caption") == "C" } }
    assert_equal 1, Media::Asset.count
  end

  test "a failed upload shows its errors inline and inserts nothing" do
    visit_post

    editor.click
    attach_file(file_fixture("fake.png").to_s) { press "Image" }

    assert_selector "[data-admin--rich-text-target='message']", text: /File/
    refute_selector ".ProseMirror img"
    assert_equal 0, Media::Asset.count
  end

  test "the internal link picker inserts an internalLink mark to an existing page" do
    target = create_page(title: "Contact")
    visit_post

    editor.click
    press "Internal link"
    within(".admin-rich-text-popover") do
      fill_in "Search pages and posts", with: "Cont"
      press "Contact"
    end

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } }
    assert_equal "Contact", linked["text"]
    assert_equal [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ], linked["marks"]
  end

  test "an external link is checked client-side before it's applied" do
    visit_post

    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL", with: "javascript:alert(1)"
      press "Apply"
      assert_text "Use an http(s), mailto or relative link"
      fill_in "URL", with: "https://example.com/docs"
      press "Apply"
    end

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } }
    assert_equal "https://example.com/docs", linked["text"]
    assert_equal [ { "type" => "link", "attrs" => { "href" => "https://example.com/docs" } } ], linked["marks"]
  end

  # Pasted HTML is parsed against the editor's own schema, so anything
  # outside `RichText::Schema` (underline, tables, H1, a `javascript:` link,
  # a bare `<img>` with no `Media::Asset` behind it) is dropped or flattened
  # to what the schema does have, never smuggled into the saved document.
  test "pasted HTML is constrained to the schema" do
    visit_post

    editor.click
    paste(html: <<~HTML, text: "fallback")
      <h1>Big title</h1>
      <p><u>under</u> <b>bold</b> <a href="javascript:alert(1)">bad</a> <a href="https://example.com" target="_blank" rel="nofollow">good</a></p>
      <table><tr><td>cell</td></tr></table>
      <img src="https://example.com/x.png">
      <ol start="3" type="a"><li>third</li></ol>
    HTML

    document = saved_post_document { |doc| doc_text(doc).include?("third") }
    json = document.to_h.to_json
    refute_includes json, "underline"
    refute_includes json, "javascript"
    refute_includes json, "table"
    refute_includes json, "_blank"
    assert nodes(document).none? { |node| node["type"] == "image" }
    assert nodes(document).none? { |node| node["type"] == "heading" && !(2..4).cover?(node.dig("attrs", "level")) }
    list = nodes(document).find { |node| node["type"] == "orderedList" }
    assert_equal({ "start" => 3 }, list["attrs"])
  end

  test "in a translation the primary-language original shows the rendered English body" do
    @post.assign_body(rich_doc("Hello **there**"), locale: :en)
    @post.save!

    visit "/cs-studio/posts/#{@post.id}?locale=de"

    assert_selector "[data-original-for='body'] strong", text: "there"
    # The German editor itself starts empty -- the original is beside it,
    # not loaded into it.
    assert_no_text_in_editor "there"
  end

  # Turbo Stream replacement of a whole block card (task 7's lifecycle
  # ruling): the old card's `admin--rich-text` disconnects (destroying its
  # editor), the new card's connects and mounts exactly one editor, and
  # typing into the new one still autosaves. Also detaches and re-attaches
  # the *same* card element (what a drag reorder does), which Stimulus
  # answers with disconnect-then-connect on one element -- the case that
  # would double-mount if `connect` didn't start from a clean mount point.
  test "a block card swapped by a Turbo Stream mounts one editor and still saves" do
    page_record = create_page(title: "About")
    block = page_record.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{page_record.id}"
    card_id = ActionView::RecordIdentifier.dom_id(block)
    await_editors(count: 1)

    page.execute_script(<<~JS, card_id)
      const id = arguments[0]
      fetch(window.location.href, { headers: { Accept: "text/html" } }).then((response) => response.text()).then((html) => {
        const fresh = new DOMParser().parseFromString(html, "text/html").getElementById(id)
        fresh.setAttribute("data-swapped", "true")
        window.Turbo.renderStreamMessage(`<turbo-stream action="replace" target="${id}"><template>${fresh.outerHTML}</template></turbo-stream>`)
      })
    JS
    assert_selector "##{card_id}[data-swapped='true'] .ProseMirror", count: 1

    page.execute_script(<<~JS, card_id)
      const card = document.getElementById(arguments[0])
      const parent = card.parentNode
      const next = card.nextSibling
      card.remove()
      window.setTimeout(() => parent.insertBefore(card, next), 50)
    JS
    assert_selector "##{card_id} .ProseMirror", count: 1
    await_editors(count: 1)

    find("##{card_id} .ProseMirror").click
    type_text "Swapped and saved"

    saved_document(block) { |doc| doc_text(doc).include?("Swapped and saved") }
  end

  # Two rich-text blocks on one page are two independent editors, each
  # writing only its own card's hidden input.
  test "typing in one of two editors on a page saves only that block" do
    page_record = create_page(title: "About")
    first = page_record.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("First"))
    second = page_record.content_blocks.create!(block_type: "rich_text", position: 1, body: rich_doc("Second"))
    visit "/cs-studio/pages/#{page_record.id}"
    await_editors(count: 2)

    find("##{ActionView::RecordIdentifier.dom_id(first)} .ProseMirror").click
    type_text " edited"

    saved_document(first) { |doc| doc_text(doc).include?("edited") }
    assert_equal rich_doc("Second"), second.reload.body_document(locale: :en).to_h
  end

  test "Escape closes a popover and returns to the editor" do
    visit_post

    editor.click
    press "Link"
    assert_selector ".admin-rich-text-popover"
    find_field("URL").send_keys(:escape)

    refute_selector ".admin-rich-text-popover"
    # Tiptap's `focus` command focuses on the next animation frame, so this
    # polls rather than reading `document.activeElement` once.
    assert_selector ".ProseMirror:focus"
  end

  # Task 7 fix round 1 (I1): a unicode URL is stored canonical (punycode
  # host, percent-encoded path) and the server accepts it.
  test "a unicode link saves" do
    visit_post

    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL", with: "https://münchen.de/über"
      press "Apply"
    end

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } }
    assert_equal "https://münchen.de/über", linked["text"]
    assert_equal [ { "type" => "link", "attrs" => { "href" => "https://xn--mnchen-3ya.de/%C3%BCber" } } ], linked["marks"]
  end

  test "a bare email address becomes a mailto link" do
    visit_post

    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL", with: "a@b.com"
      press "Apply"
    end

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } }
    assert_equal [ { "type" => "link", "attrs" => { "href" => "mailto:a@b.com" } } ], linked["marks"]
  end

  # Final fix wave (D, P10/P11): `rich_text/schema`'s href normalisation,
  # run in the browser itself (the functions are the editor's own module,
  # imported through the page's import map). An absolute href is parsed
  # without a base -- with CS Studio's origin as base, `https:example.com`
  # resolved to a path on the studio's own host -- and a bare unicode
  # domain gets `https://` like an ASCII one, instead of being stored as a
  # relative path.
  test "href normalisation handles scheme-relative-looking and unicode input" do
    visit_post

    results = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("rich_text/schema").then((schema) => done([
        schema.normalizeHref("https:example.com"),
        schema.normalizeHref("münchen.de"),
        schema.normalizeHref("straße.de/über?q=1"),
        schema.normalizeHref("example.com:8080/x"),
        schema.normalizeHref("/about"),
        schema.normalizeHref("a@b.com"),
        schema.canonicalHref("HTTPS://Example.COM/a b")
      ])).catch((error) => done(String(error)))
    JS

    assert_equal [
      "https://example.com/",
      "https://xn--mnchen-3ya.de/",
      "https://xn--strae-oqa.de/%C3%BCber?q=1",
      "https://example.com:8080/x",
      "/about",
      "mailto:a@b.com",
      "https://example.com/a%20b"
    ], results
  end

  # Task 7 fix round 1 (m2/m1): merely focusing the editor (Tiptap's
  # trailing-node plugin appends an empty paragraph after a final embed on
  # first focus) and moving focus into a popover are not edits -- neither
  # may write the hidden input or send a save.
  test "focusing the editor and opening a popover don't save anything" do
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "youtube", "attrs" => { "id" => YOUTUBE_ID } } ] }, locale: :en)
    @post.save!
    visit_post
    stored = find("input[name='post[body]']", visible: false).value
    page.execute_script(<<~JS)
      window.__patches = 0
      const originalFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "PATCH") window.__patches += 1
        return originalFetch(url, options)
      }
    JS

    editor.click
    press "Link"
    assert_selector ".admin-rich-text-popover"
    sleep 1.5

    assert_equal stored, find("input[name='post[body]']", visible: false).value
    assert_equal 0, page.evaluate_script("window.__patches")
  end

  # Final fix wave (A): what the Markdown loader (MCP's write path) builds
  # must be a document the real editor loads -- not just one the server
  # validates. Each of these used to save fine through MCP and then open
  # read-only in CS Studio ("contains something the editor can't show").
  test "documents the Markdown loader builds open editable in the editor" do
    page_record = create_page(title: "Target")
    [
      "**`x`**\n",
      "[`x`](cs:page/#{page_record.id})\n",
      "```\n```\n",
      "- \n",
      "> \n\nafter the quote\n",
      "- ::youtube{id=\"#{YOUTUBE_ID}\"}\n\n> ::youtube{id=\"#{YOUTUBE_ID}\"}\n",
      "a **b `c` d** e\\\n- flour\n\n1. one\n   - nested *x*\n"
    ].each do |markdown|
      document, = RichText::Document.from_markdown(markdown)
      assert_empty document.validate, "loader output for #{markdown.inspect} isn't valid"
      @post.assign_body(document.to_h, locale: :en)
      @post.save!

      visit_post
      assert_selector ".ProseMirror[contenteditable='true']"
      assert_no_text INVALID_CONTENT, wait: 0.5
      assert_selector "[data-admin--rich-text-command]:not([disabled])", minimum: 1
    end
  end

  private

  def visit_post
    visit "/cs-studio/posts/#{@post.id}"
    await_editors
  end

  # Every editor mounted, then `await_admin_controllers` (see
  # ApplicationSystemTestCase) before any typing.
  def await_editors(count: nil)
    count ? assert_selector(".ProseMirror", count: count) : assert_selector(".ProseMirror")
    await_admin_controllers
  end

  def editor = find(".ProseMirror")

  # Real key events (CDP `Input.dispatchKeyEvent`, through Ferrum's
  # keyboard) into whatever currently has focus (the ProseMirror element,
  # after `editor.click`) -- not `editor.send_keys`, which focuses the
  # element first and may, with it, move the caret and drop a stored mark
  # a toolbar button just set.
  def type_text(text)
    page.driver.browser.keyboard.type(text)
  end

  # A synthetic `paste` carrying a real `DataTransfer` -- ProseMirror reads
  # `event.clipboardData` exactly as it would for a native paste, and
  # headless Chrome's own clipboard is not reliably reachable from the test.
  def paste(text: nil, html: nil)
    page.execute_script(<<~JS, text, html)
      const data = new DataTransfer()
      if (arguments[0]) data.setData("text/plain", arguments[0])
      if (arguments[1]) data.setData("text/html", arguments[1])
      const target = document.querySelector(".ProseMirror")
      target.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS
  end

  # Polls the database (not the status line -- see
  # `test/system/admin/autosave_test.rb`'s "second quick edit" comment for
  # why a status line can lie about *which* save landed) until the saved
  # document satisfies `condition`, then asserts it validates.
  def saved_post_document(timeout: 6, &condition) = saved_document(@post, timeout: timeout, &condition)

  def saved_document(record, timeout: 6, &condition)
    deadline = Time.current + timeout
    document = nil
    loop do
      document = record.reload.body_document(locale: :en)
      break if condition.call(document)
      flunk "the saved document never matched: #{document.to_h.to_json}" if Time.current > deadline
      sleep 0.1
    end
    assert_empty document.validate, "the editor saved a document the server schema rejects"
    document
  end

  def nodes(document)
    stack = [ document.to_h ]
    found = []
    until stack.empty?
      node = stack.pop
      found << node
      stack.concat(Array(node["content"]).reverse)
    end
    found
  end

  def text_nodes(document) = nodes(document).select { |node| node["type"] == "text" }

  def doc_text(document) = text_nodes(document).map { |node| node["text"] }.join

  def assert_no_text_in_editor(text)
    assert_selector ".ProseMirror"
    refute_selector ".ProseMirror", text: text
  end
end
