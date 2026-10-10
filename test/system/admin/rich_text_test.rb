require "application_system_test_case"

# The Tiptap editor in CS Studio (tiptap spec §4.1/§9): `admin--rich-text--editor`
# mounts Tiptap on `Admin::Columns::RichTextColumnComponent`, writes
# `editor.getJSON()` into the column's hidden `…[body]` input and dispatches
# `input` so the form's own `admin--saving--autosave` sends it. Every test here ends
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
  # The editor's read-only notice (`admin--rich-text--editor`'s `invalidContent`).
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

  # Media library Task 8 / design pass round 2 Task 13: the Image button opens
  # the media picker; the picked asset then opens the 560 image dialog (alt
  # text and caption), and "Insert image" there inserts it after the text
  # already typed (not over it). Nothing is inserted before that.
  test "an image uploaded through the picker from the Image button is inserted through the image dialog and its alt text saved" do
    visit_post

    editor.click
    type_text "Intro"
    press_insert "Image"
    # The upload shows as a tile, which is selected once it has finished; the
    # editor confirms with Use image (select-then-use, round 3 Task 9).
    within("dialog[open]") do
      attach_file "Image file", file_fixture("tiny.png").to_s
      assert_text "1 selected", wait: 10
      click_on "Use image"
    end
    assert_selector "dialog#rich-text-image-dialog[open]"
    refute_selector ".ProseMirror img"

    within("dialog#rich-text-image-dialog[open]") do
      assert_text "Empty uses the text from Media", count: 2
      fill_in "Alt text", with: "A"
      press "Insert image"
    end
    refute_selector "dialog[open]"

    document = saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" && node.dig("attrs", "alt") == "A" } }
    image = nodes(document).find { |node| node["type"] == "image" }
    asset = Media::Asset.find(image.dig("attrs", "asset_id"))
    assert_equal({ "asset_id" => asset.id, "alt" => "A", "caption" => "" }, image["attrs"])
    assert_equal "Intro", doc_text(document).strip
    assert_selector ".ProseMirror img[src='#{asset.url}']"
    # Focus is back in the editor.
    assert_selector ".ProseMirror:focus"

    # Clicking the image edits it: the same dialog, now titled for editing
    # with "Save".
    find(".ProseMirror figure.admin-rich-text-image").click
    within("dialog#rich-text-image-dialog[open]") do
      assert_selector "h2", text: "Edit image"
      assert_field "Alt text", with: "A"
      fill_in "Caption", with: "C"
      press "Save"
    end
    saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" && node.dig("attrs", "caption") == "C" } }
    assert_equal 1, Media::Asset.count
  end

  # Review C, M22: the toolbar route to editing a selected image. An inserted
  # image is left node-selected, so Insert, Image then edits it instead of
  # inserting another.
  test "Insert, Image with an image selected edits that image through the toolbar" do
    asset = create_media_asset
    asset.update!(title: "Lake")
    visit_post
    editor.click
    press_insert "Image"
    within("dialog[open]") { click_on "Lake"; click_on "Use image" }
    within("dialog#rich-text-image-dialog[open]") { press "Insert image" }
    refute_selector "dialog[open]"
    saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" } }

    press_insert "Image"
    within("dialog#rich-text-image-dialog[open]") do
      assert_selector "h2", text: "Edit image"
      fill_in "Caption", with: "Via the toolbar"
      press "Save"
    end
    document = saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" && node.dig("attrs", "caption") == "Via the toolbar" } }
    assert_equal 1, nodes(document).count { |node| node["type"] == "image" }
  end

  test "the image dialog shows the library text as placeholders, an empty one leaves the node without overrides, and Cancel inserts nothing" do
    asset = create_media_asset
    asset.update!(title: "Lake", alt: "A calm lake", caption: "Lake at dawn")
    visit_post

    editor.click
    press_insert "Image"
    within("dialog[open]") { click_on "Lake"; click_on "Use image" }
    within("dialog#rich-text-image-dialog[open]") do
      assert_field "Alt text", with: "", placeholder: "A calm lake"
      assert_field "Caption", with: "", placeholder: "Lake at dawn"
      press "Cancel"
    end
    refute_selector "dialog[open]"
    refute_selector ".ProseMirror figure"
    assert_selector ".ProseMirror:focus"

    press_insert "Image"
    within("dialog[open]") { click_on "Lake"; click_on "Use image" }
    within("dialog#rich-text-image-dialog[open]") { press "Insert image" }

    document = saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "image" } }
    image = nodes(document).find { |node| node["type"] == "image" }
    assert_equal({ "asset_id" => asset.id, "alt" => "", "caption" => "" }, image["attrs"])
  end

  test "a failed upload in the picker shows its errors inline and inserts nothing" do
    visit_post

    editor.click
    press_insert "Image"
    within("dialog[open]") do
      attach_file "Image file", file_fixture("fake.png").to_s
      # The refused file keeps its tile, with the server's reason and Dismiss.
      assert_selector "[data-upload-tile]", text: /PNG, JPEG, GIF, or WEBP/, wait: 10
      assert_button "Dismiss"
      assert_button "Use image", disabled: true
    end

    refute_selector ".ProseMirror img"
    assert_equal 0, Media::Asset.count
  end

  test "Insert > Page link opens the page dialog and inserts an internalLink mark to the picked page" do
    target = create_page(title: "Contact")
    visit_post

    editor.click
    press_insert "Page link"
    within("dialog#rich-text-page-dialog[open]") do
      fill_in "Search pages and posts", with: "Cont"
      assert_selector "[role=option]", text: "Contact"
      find("[role=option]", text: "Contact").click
    end
    refute_selector "dialog[open]"

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } }
    assert_equal "Contact", linked["text"]
    assert_equal [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ], linked["marks"]
    assert_selector ".ProseMirror:focus"
  end

  test "the Link popover searches pages and posts: picking a row makes an internalLink, typing a URL and Enter makes a link" do
    target = create_page(title: "About")
    visit_post

    editor.click
    type_text "see this"
    select_editor_text
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL or search", with: "abo"
      assert_selector "[role=option]", text: "About"
      find("[role=option]", text: "About").click
    end
    refute_selector ".admin-rich-text-popover"

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } }
    assert_equal "see this", linked["text"]
    assert_equal [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ], linked["marks"]

    # An external one over the same text: the typed URL, Enter -- not the
    # first search row.
    select_editor_text
    press "Link"
    within(".admin-rich-text-popover") do
      assert_button "Remove link"
      fill_in "URL or search", with: "https://example.org"
      find_field("URL or search").send_keys(:enter)
    end
    refute_selector ".admin-rich-text-popover"

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } } }
    linked = text_nodes(document).find { |node| Array(node["marks"]).any? { |mark| mark["type"] == "link" } }
    assert_equal [ "link" ], linked["marks"].map { |mark| mark["type"] }
    assert_match %r{\Ahttps://example\.org/?\z}, linked["marks"].first.dig("attrs", "href")
    assert_not text_nodes(document).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } }
  end

  # A Turbo Stream can replace the block card an open dialog belongs to; the
  # dialog has nobody to answer then, so it closes instead of applying to a
  # different editor.
  test "a dialog whose editor is replaced while it is open closes without inserting anything" do
    page_record = create_page(title: "About")
    block = page_record.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Body"))
    visit "/cs-studio/pages/#{page_record.id}"
    await_editors(count: 1)
    card_id = ActionView::RecordIdentifier.dom_id(block)

    find("##{card_id} .ProseMirror").click
    press_insert "YouTube"
    assert_selector "dialog#rich-text-youtube-dialog[open]"
    page.execute_script(<<~JS, card_id)
      const id = arguments[0]
      const card = document.getElementById(id)
      window.Turbo.renderStreamMessage(`<turbo-stream action="replace" target="${id}"><template>${card.outerHTML}</template></turbo-stream>`)
    JS
    refute_selector "dialog[open]"
    assert_selector "##{card_id} .ProseMirror", count: 1
    refute_selector ".ProseMirror [data-youtube-id]"
  end

  # --- Fix round 1 (Task 13) ------------------------------------------------

  test "reopening the page dialog never piles up listeners: one pick applies exactly one link, to the picked page" do
    target = create_page(title: "Contact")
    create_page(title: "Contract")
    visit_post

    editor.click
    2.times do
      press_insert "Page link"
      within("dialog#rich-text-page-dialog[open]") do
        fill_in "Search pages and posts", with: "Cont"
        assert_selector "[role=option]", minimum: 1
        press "Cancel"
      end
      refute_selector "dialog[open]"
      # A closed dialog's search is torn down: nothing of it is left in the
      # persistent list.
      assert_no_selector "#rich-text-page-dialog [role=option]", visible: :all
    end
    press_insert "Page link"
    within("dialog#rich-text-page-dialog[open]") do
      fill_in "Search pages and posts", with: "Cont"
      assert_selector "[role=option]", text: "Contact"
      find("[role=option]", text: "Contact").click
    end
    refute_selector "dialog[open]"

    document = saved_post_document { |doc| doc_text(doc).include?("Contact") }
    assert_equal "Contact", doc_text(document)
    marks = text_nodes(document).flat_map { |node| Array(node["marks"]) }
    assert_equal [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ], marks
  end

  test "Escape closes the suggestion list first and only a second Escape closes the dialog" do
    create_page(title: "Contact")
    visit_post

    editor.click
    press_insert "Page link"
    within("dialog#rich-text-page-dialog[open]") do
      fill_in "Search pages and posts", with: "Cont"
      assert_selector "[role=option]"
      find_field("Search pages and posts").send_keys(:escape)
      assert_no_selector "[role=option]"
    end
    assert_selector "dialog#rich-text-page-dialog[open]"
    find_field("Search pages and posts").send_keys(:escape)
    refute_selector "dialog[open]"

    # The same in the Link popover.
    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL or search", with: "Cont"
      assert_selector "[role=option]"
      find_field("URL or search").send_keys(:escape)
      assert_no_selector "[role=option]"
    end
    assert_selector ".admin-rich-text-popover"
    find_field("URL or search").send_keys(:escape)
    refute_selector ".admin-rich-text-popover"
  end

  test "picking a page with the caret inside an external link converts that link instead of inserting text" do
    target = create_page(title: "About")
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "linked", "marks" => [ { "type" => "link", "attrs" => { "href" => "https://example.org/" } } ] } ] } ] }, locale: :en)
    @post.save!
    visit_post

    find(".ProseMirror a[href]").click
    press_insert "Page link"
    within("dialog#rich-text-page-dialog[open]") do
      fill_in "Search pages and posts", with: "Abo"
      find("[role=option]", text: "About").click
    end
    refute_selector "dialog[open]"

    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } } }
    assert_equal "linked", doc_text(document)
    assert_equal [ [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ] ], text_nodes(document).map { |node| node["marks"] }
  end

  test "Enter on a plain word applies nothing and says what to do; real URLs and paths are accepted" do
    visit_post
    editor.click
    type_text "target"

    [ "abo", "v1.2" ].each do |word|
      select_editor_text
      press "Link"
      within(".admin-rich-text-popover") do
        fill_in "URL or search", with: word
        find_field("URL or search").send_keys(:enter)
        assert_selector "[role=alert]", text: "Pick a page, or enter a URL"
        find_field("URL or search").send_keys(:escape)
      end
      refute_selector ".admin-rich-text-popover"
    end
    assert_writes_settled # the typed text's own save has gone out and been answered: whatever it saved is on the record now
    assert_empty text_nodes(@post.reload.body_document(locale: :en)).flat_map { |node| Array(node["marks"]) }

    { "example.com" => "example.com", "/about" => "/about", "#top" => "#top", "mailto:a@b.c" => "mailto:a@b.c" }.each do |typed, saved|
      select_editor_text
      press "Link"
      within(".admin-rich-text-popover") do
        fill_in "URL or search", with: typed
        find_field("URL or search").send_keys(:enter)
      end
      refute_selector ".admin-rich-text-popover"
      saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark.dig("attrs", "href").to_s.include?(saved) } } }
    end
  end

  test "arrow keys move through the rows with aria-activedescendant and Enter picks the highlighted one" do
    target = create_page(title: "Zeta")
    create_page(title: "Zebra")
    visit_post

    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL or search", with: "Ze"
      assert_selector "[role=option]", count: 2
      field = find_field("URL or search")
      assert_nil field["aria-activedescendant"]
      field.send_keys(:down)
      first = find("[role=option][aria-selected=true]")
      assert_equal first[:id], field["aria-activedescendant"]
      field.send_keys(:down)
      second = find("[role=option][aria-selected=true]")
      assert_not_equal first[:id], second[:id]
      assert_equal second[:id], field["aria-activedescendant"]
      chosen = second.text
      field.send_keys(:enter)
      @chosen = chosen
    end
    document = saved_post_document { |doc| text_nodes(doc).any? { |node| Array(node["marks"]).any? { |mark| mark["type"] == "internalLink" } } }
    assert_includes @chosen, doc_text(document)
    assert_equal target.id, text_nodes(document).first["marks"].first.dig("attrs", "id") if doc_text(document) == "Zeta"
  end

  test "a slow answer for an earlier query never replaces the rows for the current one" do
    create_page(title: "Alpha")
    create_page(title: "Beta")
    visit_post

    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => {
        if (String(url).includes("link_targets") && String(url).includes("q=alp")) {
          window.__alpAsked = true
          return new Promise((resolve) => setTimeout(() => resolve(original(url, { ...options, signal: undefined }).then((response) => { window.__alpDelivered = true; return response })), 1200))
        }
        return original(url, options)
      }
    JS
    editor.click
    press "Link"
    within(".admin-rich-text-popover") do
      fill_in "URL or search", with: "alp"
      await_js "window.__alpAsked === true" # the first query is out, and held for 1.2 s
      fill_in "URL or search", with: "bet"
      assert_selector "[role=option]", text: "Beta"
      await_js "window.__alpDelivered === true" # the slow answer for "alp" has now reached the search
      await_frames
      assert_selector "[role=option]", text: "Beta"
      assert_no_selector "[role=option]", text: "Alpha"
    end
  end

  test "the Link popover is prefilled with an existing link's URL" do
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "linked", "marks" => [ { "type" => "link", "attrs" => { "href" => "https://example.org/docs" } } ] } ] } ] }, locale: :en)
    @post.save!
    visit_post

    find(".ProseMirror a[href]").click
    press "Link"
    within(".admin-rich-text-popover") do
      assert_field "URL or search", with: "https://example.org/docs"
      assert_button "Remove link"
    end
  end

  test "Remove image in the image dialog deletes the node, and an unchanged Save writes nothing" do
    asset = create_media_asset
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "A", "caption" => "" } } ] }, locale: :en)
    @post.save!
    visit_post
    updated_at = @post.reload.updated_at

    find(".ProseMirror figure.admin-rich-text-image").click
    within("dialog#rich-text-image-dialog[open]") { press "Save" }
    refute_selector "dialog[open]"
    assert_writes_settled # an autosave the dialog's Save started has been sent and answered
    assert_equal updated_at, @post.reload.updated_at

    find(".ProseMirror figure.admin-rich-text-image").click
    within("dialog#rich-text-image-dialog[open]") { press "Remove image" }
    refute_selector "dialog[open]"
    refute_selector ".ProseMirror figure"
    saved_post_document { |doc| nodes(doc).none? { |node| node["type"] == "image" } }
  end

  test "Remove link in the page dialog removes an internal link" do
    target = create_page(title: "About")
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "linked", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ] } ] } ] }, locale: :en)
    @post.save!
    visit_post

    find(".ProseMirror a[data-internal-link]").click
    press_insert "Page link"
    within("dialog#rich-text-page-dialog[open]") { press "Remove link" }
    refute_selector "dialog[open]"
    saved_post_document { |doc| text_nodes(doc).none? { |node| Array(node["marks"]).any? } }
  end

  test "an inserted image is selected, so Enter edits it" do
    create_media_asset
    visit_post

    editor.click
    press_insert "Image"
    within("dialog[open]") { click_on Media::Asset.last.title; click_on "Use image" }
    within("dialog#rich-text-image-dialog[open]") { press "Insert image" }
    refute_selector "dialog[open]"
    assert_selector ".ProseMirror figure.is-selected"
    page.driver.browser.keyboard.type(:enter)
    assert_selector "dialog#rich-text-image-dialog[open] h2", text: "Edit image"
  end

  test "Remove link in the Link popover removes an internal link" do
    target = create_page(title: "About")
    @post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "linked", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ] } ] } ] }, locale: :en)
    @post.save!
    visit_post

    find(".ProseMirror a[data-internal-link]").click
    press "Link"
    within(".admin-rich-text-popover") { press "Remove link" }

    document = saved_post_document { |doc| text_nodes(doc).none? { |node| Array(node["marks"]).any? } }
    assert_equal "linked", doc_text(document)
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

  # The page editor sits beside the tree, so at 1100px a block card's form is
  # under 880px wide: the original (reference card) stacks ABOVE the editor
  # (design pass round 2, Task 7), which leaves the toolbar the whole column.
  # It stays inside its own box -- no tool pokes out sideways, and the
  # original is above it, not beside it -- and the Insert menu still opens.
  # (Round 1's `flex-wrap` remains the fallback for a column narrower still.)
  test "in a narrow translation column (page editor beside the tree) the original stacks above the toolbar, which stays inside its box, and the Insert menu stays reachable" do
    page.driver.resize(1100, 1000)
    page_record = create_page(title: "About")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } }).record
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_editors
    assert_selector "[data-original-for='body']"

    spill = page.evaluate_script(<<~JS)
      (() => {
        const toolbar = document.querySelector("#block-#{block.id} [role=toolbar], [role=toolbar]")
        const original = document.querySelector("[data-original-for='body']")
        const t = toolbar.getBoundingClientRect(), o = original.getBoundingClientRect()
        const inside = Array.from(toolbar.querySelectorAll("button")).filter((b) => b.offsetParent).every((b) => {
          const r = b.getBoundingClientRect()
          return r.right <= t.right + 0.5 && r.left >= t.left - 0.5
        })
        return { inside, clear: o.bottom <= t.top + 0.5 }
      })()
    JS
    assert spill["inside"], "a toolbar tool sits outside the toolbar's box"
    assert spill["clear"], "the original should stack above the toolbar, not overlap it"
    find("[role=toolbar] button[aria-haspopup=menu]").click
    assert_selector "[role=toolbar] [role=menu] button", text: "YouTube", visible: true
  ensure
    page.driver.resize(1400, 1400)
  end

  # Design pass round 1, bug 5: with the primary-language original shown
  # beside the editor (half the column each) the toolbar used to wrap onto
  # several rows. It is one row now, and the Insert menu -- which sits inside
  # the toolbar -- is neither clipped by it nor out of reach: its items are
  # visible, inside the viewport, and still run their command.
  test "in a translation the toolbar is one row and the Insert menu opens and runs YouTube" do
    page.driver.resize(1400, 1000)
    @post.assign_body(rich_doc("Hello **there**"), locale: :en)
    @post.save!
    visit "/cs-studio/posts/#{@post.id}?locale=de"
    await_editors
    assert_selector "[data-original-for='body']"

    rows = page.evaluate_script("(() => { const t = document.querySelector('[role=toolbar]'); const tops = new Set(Array.from(t.children).map(c => c.getBoundingClientRect().top)); return tops.size })()")
    assert_equal 1, rows
    # Nothing spills out of the toolbar sideways either.
    assert page.evaluate_script("(() => { const t = document.querySelector('[role=toolbar]'); return t.scrollWidth <= t.clientWidth })()"),
      "the toolbar's tools overflow its box"

    editor.click
    find("[role=toolbar] button[aria-haspopup=menu]").click
    assert_selector "[role=toolbar] [role=menu] button", text: "YouTube", visible: true
    # The open panel is really on screen: the element at the item's centre is
    # the item itself, not the toolbar or the editor clipping/covering it.
    on_top = page.evaluate_script(<<~JS)
      (() => {
        const item = Array.from(document.querySelectorAll("[role=toolbar] [role=menu] button")).find((b) => b.textContent.trim() === "YouTube")
        const box = item.getBoundingClientRect()
        const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
        return item === hit || item.contains(hit)
      })()
    JS
    assert on_top, "the Insert menu's YouTube item is covered or clipped"
    page.find("[role=toolbar] [role=menu] button", text: "YouTube").click

    assert_no_selector "[role=toolbar] [role=menu]", visible: true
    within("dialog#rich-text-youtube-dialog[open]") do
      fill_in "YouTube URL or video ID", with: "https://www.youtube.com/watch?v=#{YOUTUBE_ID}"
      press "Insert video"
    end
    assert_selector ".ProseMirror [data-youtube-id='#{YOUTUBE_ID}']"
  ensure
    page.driver.resize(1400, 1400)
  end

  test "the YouTube dialog rejects text that is not a video, shows the id live, and Enter inserts" do
    visit_post

    editor.click
    press_insert "YouTube"
    within("dialog#rich-text-youtube-dialog[open]") do
      fill_in "YouTube URL or video ID", with: "hello"
      press "Insert video"
      assert_text "That doesn’t look like a YouTube link."
      assert_selector "#rich-text-youtube-url[aria-invalid=true]"
      fill_in "YouTube URL or video ID", with: "https://www.youtube.com/watch?v=#{YOUTUBE_ID}"
      assert_no_text "That doesn’t look like a YouTube link."
      assert_text "Video id: #{YOUTUBE_ID}"
      find_field("YouTube URL or video ID").send_keys(:enter)
    end
    refute_selector "dialog[open]"
    assert_selector ".ProseMirror [data-youtube-id='#{YOUTUBE_ID}']"
    # Enter applied the dialog: it did not submit the editor's form.
    assert_current_path "/cs-studio/posts/#{@post.id}"
    saved_post_document { |doc| nodes(doc).any? { |node| node["type"] == "youtube" } }
  end

  # Review B, M3: a refused Insert marks the field invalid; the next opening
  # starts clean -- no message, and no invalid border without one.
  test "the YouTube dialog reopens without the invalid mark a refused Insert left" do
    visit_post

    editor.click
    press_insert "YouTube"
    within("dialog#rich-text-youtube-dialog[open]") do
      fill_in "YouTube URL or video ID", with: "hello"
      press "Insert video"
      assert_selector "#rich-text-youtube-url[aria-invalid=true]"
      press "Cancel"
    end
    refute_selector "dialog[open]"

    press_insert "YouTube"
    within("dialog#rich-text-youtube-dialog[open]") do
      assert_field "YouTube URL or video ID", with: ""
      assert_no_selector "#rich-text-youtube-url[aria-invalid]"
      assert_no_text "That doesn’t look like a YouTube link."
    end
  end

  test "Escape and Cancel close a dialog, insert nothing and return focus to the editor" do
    visit_post

    editor.click
    press_insert "YouTube"
    find_field("YouTube URL or video ID").send_keys(:escape)
    refute_selector "dialog[open]"
    assert_selector ".ProseMirror:focus"

    press_insert "YouTube"
    within("dialog#rich-text-youtube-dialog[open]") { press "Cancel" }
    refute_selector "dialog[open]"
    assert_selector ".ProseMirror:focus"
    refute_selector ".ProseMirror [data-youtube-id]"
  end

  # Dialogs live once in the layout, so which editor asked is the only thing
  # that decides who gets the answer.
  test "with two rich-text blocks on a page, a dialog opened from the second changes only the second" do
    page_record = create_page(title: "About")
    first = page_record.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("First"))
    second = page_record.content_blocks.create!(block_type: "rich_text", position: 1, body: rich_doc("Second"))
    visit "/cs-studio/pages/#{page_record.id}"
    await_editors(count: 2)

    second_card = "##{ActionView::RecordIdentifier.dom_id(second)}"
    find("#{second_card} .ProseMirror").click
    within(second_card) { press_insert "YouTube" }
    within("dialog#rich-text-youtube-dialog[open]") do
      fill_in "YouTube URL or video ID", with: YOUTUBE_ID
      press "Insert video"
    end

    assert_selector "#{second_card} .ProseMirror [data-youtube-id='#{YOUTUBE_ID}']"
    saved_document(second) { |doc| nodes(doc).any? { |node| node["type"] == "youtube" } }
    assert_selector "##{ActionView::RecordIdentifier.dom_id(first)} .ProseMirror", text: "First"
    refute_selector "##{ActionView::RecordIdentifier.dom_id(first)} .ProseMirror [data-youtube-id]"
    assert_equal rich_doc("First"), first.reload.body_document(locale: :en).to_h
  end

  # Turbo Stream replacement of a whole block card (task 7's lifecycle
  # ruling): the old card's `admin--rich-text--editor` disconnects (destroying its
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
    assert_writes_settled # a save the focus or the popover queued has been sent and answered

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
      assert_selector "[data-admin--rich-text--editor-command]:not([disabled])", minimum: 1
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

  # Selects everything in the (first) editor, so a toolbar command applies to it.
  def select_editor_text
    page.execute_script(<<~JS)
      const el = document.querySelector(".ProseMirror")
      el.focus()
      const range = document.createRange()
      range.selectNodeContents(el)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    JS
    # ProseMirror learns of a DOM selection from a `selectionchange` event,
    # handled a frame or two later: wait that out before a command reads it.
    page.evaluate_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(() => done(true), 50)))")
  end

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
    document = nil
    assert_eventually(wait: timeout, message: -> { "the saved document never matched: #{document.to_h.to_json}" }) do
      document = record.reload.body_document(locale: :en)
      condition.call(document)
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
