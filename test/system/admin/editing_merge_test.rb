require "application_system_test_case"

# The merge rule by itself (`app/javascript/editing/merge.js`): "a form that
# holds unsaved changes is never replaced, and neither is anything else of its
# unit; everything else is replaced by what was fetched". The module is
# imported in the browser and called directly, with the answer the server
# gives for that part at that moment and the predicate the live controller
# will hand it (the write queue's own question, asked of a form's autosave
# controller), the way `notes_merge_test.rb` calls the notes' merge: no cable
# connection, no controller of the live editor in between.
class Admin::EditingMergeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing", published: false)
    @first = add_block
    @second = add_block
    @section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    @inside = add_block(section_id: @section.id, section_column: 1)
    sign_in_via_form(users(:one))
    open_editor
  end

  def open_editor(path = "/cs-studio/pages/#{@page.id}")
    visit path
    await_admin_controllers
    # `window.Stimulus` is the application, as `app/javascript/controllers/application.js` exposes it.
    page.execute_script(<<~JS)
      window.__merge = import("editing/merge")
      window.__unsaved = (form) => {
        const autosave = window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
        return Boolean(autosave) && (!autosave.clean() || autosave.outstanding() || !autosave.unchanged())
      }
      window.__fresh = async (path) => {
        const body = new DOMParser().parseFromString(await (await fetch(path)).text(), "text/html").body
        return body
      }
    JS
  end

  def add_block(**placement)
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", **placement }).record
  end

  def card(block) = "#content_block_#{block.id}"

  def panel(block) = "#block-#{block.id}-panel"

  def blocks_path(block = nil) = "/cs-studio/editing/page/#{@page.id}/blocks#{"/#{block.id}" if block}"

  # The ids of the page's top-level blocks as the server has them now.
  def server_order = BlockOutline.new(@page.content_blocks.reload).top_level.map(&:id)

  def list_order = page.evaluate_script("Array.from(document.querySelectorAll('#content-blocks-list > [data-block-id]')).map((each) => Number(each.dataset.blockId))")

  # What a colleague does: the service, as another user, from outside the browser.
  # Unheard: these tests call the module by itself, "no controller of the live
  # editor in between", and the live controller would otherwise draw the
  # colleague's change into the page on its own while the test measures it.
  def colleague(&) = as_unheard(users(:two), &)

  # Types into the block's rich-text field without letting the debounce send it: the autosave's debounce is
  # raised on the form first, so the form is unsaved for as long as the test needs.
  def type_unsaved(block, text, within: card(block))
    raise_debounce("#{within} form[data-controller~='admin--saving--autosave']")
    field = find("#{within} .ProseMirror", visible: :all)
    field.click
    field.send_keys(text)
  end

  # Raises the debounce, and stops the form sending when the focus leaves it (`focusout` -> `saveNow`): a test that
  # types into two forms one after the other would otherwise save the first. What the form holds stays unsaved.
  def raise_debounce(form_selector)
    page.execute_script(<<~JS)
      const form = document.querySelector(#{form_selector.to_json})
      form.setAttribute("data-admin--saving--autosave-debounce-value", 600000)
      window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave").saveNow = () => {}
    JS
  end

  def keep(selector, as_name) = page.execute_script("window.#{as_name} = document.querySelector(#{selector.to_json})")

  def same?(as_name, selector) = page.evaluate_script("window.#{as_name} === document.querySelector(#{selector.to_json})")

  # Runs `body` (JS) with `merge`, `list` (#content-blocks-list) and `fresh` (the answer of `path`) in scope; `body`
  # calls `done(value)` itself, so a test can read the screen in the same task as the merge.
  def run_merge(path, body)
    page.evaluate_async_script(<<~JS, path)
      const [ path, done ] = arguments
      Promise.all([ window.__merge, window.__fresh(path) ]).then(([ merge, fresh ]) => {
        const list = document.getElementById("content-blocks-list")
        #{body}
      })
    JS
  end

  def merge_list(path = blocks_path, only_changed: false)
    run_merge(path, <<~JS)
      const result = merge.anchored(list, () => merge.mergeList(list, fresh, { unsaved: window.__unsaved, onlyChanged: #{only_changed} }))
      done({ kept: result.kept.map((each) => each.id), gone: result.gone.map((each) => each.id), moved: result.moved.map((each) => each.id), same: result.same.map((each) => each.id) })
    JS
  end

  def merge_units(path, root_id = "content-blocks-list")
    page.evaluate_async_script(<<~JS, path, root_id)
      const [ path, rootId, done ] = arguments
      Promise.all([ window.__merge, window.__fresh(path) ]).then(([ merge, fresh ]) => {
        const result = merge.mergeUnits(document.getElementById(rootId), fresh, { unsaved: window.__unsaved })
        done({ replaced: result.replaced.map((each) => each.id), kept: result.kept.map((each) => each.id), missing: result.missing, moved: result.moved.map((each) => each.id) })
      })
    JS
  end

  def text_of(selector) = page.evaluate_script("document.querySelector(#{selector.to_json})?.textContent")

  test "a card that holds unsaved text is the same element with its text after a list merge, and a clean one is replaced" do
    type_unsaved(@first, "half a sentence")
    page.execute_script("window.__a = document.querySelector(#{card(@first).to_json}); window.__b = document.querySelector(#{card(@second).to_json})")
    colleague { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }

    result = merge_list

    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert page.evaluate_script("window.__a === document.querySelector(#{card(@first).to_json})")
    assert_not page.evaluate_script("window.__b === document.querySelector(#{card(@second).to_json})")
    assert_selector "#{card(@first)} .ProseMirror", text: "half a sentence"
    assert_selector "#{card(@second)} .ProseMirror", text: "Theirs"

    # The editor inside the kept card is the one that was there: it still takes typing, and the caret is where it was.
    find("#{card(@first)} .ProseMirror").send_keys(" and more")
    assert_selector "#{card(@first)} .ProseMirror", text: "half a sentence and more"
  end

  # CATCH-UP (`onlyChanged`): what has not changed is left alone.
  test "a catch-up leaves a card of the same version as it is, with its menu open, and replaces one that changed" do
    colleague { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }
    find("#{card(@first)} button[aria-label='Block actions']").click
    assert_selector "#{card(@first)} [role=menu]"
    page.execute_script("window.__a = document.querySelector(#{card(@first).to_json}); window.__b = document.querySelector(#{card(@second).to_json})")

    result = merge_list(only_changed: true)

    assert_includes result["same"], "content_block_#{@first.id}"
    assert_not_includes result["same"], "content_block_#{@second.id}"
    assert page.evaluate_script("window.__a === document.querySelector(#{card(@first).to_json})"), "an unchanged card was replaced"
    assert_selector "#{card(@first)} [role=menu]"
    assert_not page.evaluate_script("window.__b === document.querySelector(#{card(@second).to_json})"), "a changed card was not replaced"
    assert_selector "#{card(@second)} .ProseMirror", text: "Theirs"
  end

  test "a catch-up of a page with a section leaves no id on the page twice, whatever it kept" do
    result = merge_list(only_changed: true)

    assert_includes result["same"], "content_block_#{@inside.id}", "a section's tile is left in place by a catch-up"
    ids = page.evaluate_script("(() => { const seen = {}; document.querySelectorAll('[id]').forEach((each) => { seen[each.id] = (seen[each.id] || 0) + 1 }); return Object.entries(seen).filter(([ id, count ]) => count > 1).map(([ id ]) => id) })()")
    assert_equal [], ids
  end

  test "after a catch-up a panel's heading names the column the block is in now, although only its place changed" do
    colleague do
      assert ContentBlocks::Reorder.call(@page.reload, [ @inside.id ], section: @section.id, column: 2, moved_from: { @inside.id => { section_id: @section.id, column: 1 } }).ok?
    end

    merge_list(only_changed: true)

    assert_match(/column 2/i, page.evaluate_script("document.getElementById('block-#{@inside.id}-panel').textContent"))
  end

  test "a clean element of the same version under a level the answer lacks is removed with it, never marked gone" do
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const root = document.createElement("div")
        root.innerHTML = '<div id="outer"><div id="inner"><div id="x" data-editing-unit data-editing-subject="block-9" data-editing-version="1"></div></div></div>'
        document.body.append(root)
        const fresh = document.createElement("div")
        fresh.innerHTML = '<div id="inner"><div id="x" data-editing-unit data-editing-subject="block-9" data-editing-version="1"></div></div>'
        const x = root.querySelector("#x")
        const out = merge.mergeList(root, fresh, { unsaved: () => false, onlyChanged: true })
        done({ gone: out.gone.length, marked: x.hasAttribute("data-editing-gone"), connected: x.isConnected })
        root.remove()
      })
    JS

    assert_equal 0, result["gone"]
    assert_equal false, result["marked"]
  end

  test "a part the caller holds is left as it is, and the part is not marked gone" do
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const root = document.createElement("div")
        root.innerHTML = '<div id="t" data-editing-part data-editing-subject="block-9" data-editing-version="1"><span id="menu">open</span></div>'
        document.body.append(root)
        const fresh = document.createElement("div")
        fresh.innerHTML = '<div id="t" data-editing-part data-editing-subject="block-9" data-editing-version="2"><span id="menu">new</span></div>'
        const tile = root.querySelector("#t")
        const held = merge.mergeList(root, fresh.cloneNode(true), { unsaved: () => false, hold: () => true })
        const same = root.querySelector("#t") === tile
        merge.mergeList(root, fresh, { unsaved: () => false })
        done({ same, replacedAfter: root.querySelector("#t") !== tile, kept: held.kept.length })
        root.remove()
      })
    JS

    assert_equal true, result["same"]
    assert_equal true, result["replacedAfter"]
    assert_equal 1, result["kept"]
  end

  test "without the option every clean card is replaced, as before" do
    page.execute_script("window.__a = document.querySelector(#{card(@first).to_json})")

    result = merge_list

    assert_equal [], result["same"]
    assert_not page.evaluate_script("window.__a === document.querySelector(#{card(@first).to_json})")
  end

  test "a catch-up puts a card of the same version in its new place among its siblings, and does not replace it" do
    fourth = add_block
    open_editor
    page.execute_script("window.__a = document.querySelector(#{card(@second).to_json})")
    colleague { assert ContentBlocks::Reorder.call(@page.reload, [ @first.id, @section.id, @second.id, fourth.id ]).ok? }

    result = merge_list(only_changed: true)

    assert_includes result["same"], "content_block_#{@second.id}"
    assert page.evaluate_script("window.__a === document.querySelector(#{card(@second).to_json})")
    assert_equal server_order, list_order
  end

  test "a replaced card carries the base its next save needs" do
    colleague { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }

    merge_list

    assert_equal @second.reload.updated_at.iso8601(6), find("#block-#{@second.id}-base-updated-at", visible: :all).value
  end

  test "an added block appears in its place, a moved one snaps to its place and a deleted one goes, with no card of the list left twice" do
    added = colleague { add_block }
    colleague { assert ContentBlocks::Reorder.call(@page, server_order.reverse).ok? }
    colleague { assert ContentBlocks::Destroy.call(ContentBlock.find(@second.id)).ok? }

    merge_list

    assert_includes server_order, added.id
    assert_not_includes server_order, @second.id
    assert_equal server_order, list_order
    assert_equal list_order.uniq, list_order
    assert_equal 1, page.evaluate_script("document.querySelectorAll('#content_block_#{added.id}').length")
  end

  test "a block deleted while its form holds unsaved text stays, marked gone" do
    type_unsaved(@second, "my words")
    keep(card(@second), "__a")
    colleague { assert ContentBlocks::Destroy.call(ContentBlock.find(@second.id)).ok? }

    result = merge_list

    assert_equal [ "content_block_#{@second.id}" ], result["gone"]
    assert same?("__a", card(@second))
    assert_equal "true", find(card(@second), visible: :all)["data-editing-gone"]
    assert_selector "#{card(@second)} .ProseMirror", text: "my words"
    assert_equal list_order.uniq, list_order
  end

  # Opens the block's panel through its tile, types into it, and closes it through the tile again. `type_unsaved`
  # has taken the form's `saveNow` away, so closing sends nothing (it would otherwise, by design:
  # `admin--editor--section#close`), and the panel is hidden with its text unsent.
  def hidden_panel_with(block, text)
    find("#{card(block)} .admin-block-tile__face").click
    assert_selector panel(block), visible: :visible
    type_unsaved(block, text, within: panel(block))
    find("#{card(block)} .admin-block-tile__face").click
    assert page.evaluate_script("document.querySelector(#{panel(block).to_json}).hidden")
  end

  # No id of the list is on the page twice.
  def duplicate_ids = page.evaluate_script(<<~JS)
    (() => {
      const seen = new Set(), twice = []
      for (const each of document.querySelectorAll("#content-blocks-list [id]")) { if (seen.has(each.id)) twice.push(each.id); seen.add(each.id) }
      return twice
    })()
  JS

  # How many autosave forms the document has for this block (its base field is one per form).
  def forms_of(block) = page.evaluate_script("document.querySelectorAll('#block-#{block.id}-base-updated-at').length")

  # Starts recording every node taken out of the list, and remembers `selector`'s element: afterwards `taken_out?`
  # says whether that element was ever removed from the document (a move is a removal and an insertion; being drawn
  # around is neither), which is what disconnects its controllers.
  def watch(selector)
    page.execute_script(<<~JS)
      window.__watched = document.querySelector(#{selector.to_json})
      window.__removed = []
      new MutationObserver((records) => records.forEach((record) => record.removedNodes.forEach((node) => window.__removed.push(node))))
        .observe(document.getElementById("content-blocks-list"), { childList: true, subtree: true })
    JS
  end

  def taken_out? = page.evaluate_script("window.__removed.includes(window.__watched)")

  def move_into_section(block, section, column: 1)
    colleague do
      assert ContentBlocks::Reorder.call(@page, (ContentBlock.where(section_id: section.id, section_column: column).order(:position).pluck(:id) + [ block.id ]), section: section.id, column: column,
        moved_from: { block.id => { section_id: block.section_id.to_s, column: block.section_column.to_s } }).ok?
    end
  end

  test "a hidden panel that holds unsaved text is the same element after a list merge, and stays hidden" do
    @other = add_block(section_id: @section.id, section_column: 2)
    open_editor
    hidden_panel_with(@inside, "typed in a panel")
    keep(panel(@inside), "__a")
    keep(card(@inside), "__tile")
    keep(panel(@other), "__other")
    colleague { assert ContentBlocks::Save.call(ContentBlock.find(@inside.id), translations: { "en" => { body: rich_doc("Theirs") } }).ok? }
    added = colleague { add_block(section_id: @section.id, section_column: 1) }

    result = merge_list

    assert_equal [ "block-#{@inside.id}-panel" ], result["kept"]
    assert_equal [], result["gone"]
    assert same?("__a", panel(@inside))
    assert page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).hidden")
    assert_equal "false", find("#{card(@inside)} .admin-block-tile__face", visible: :all)["aria-expanded"]
    assert_includes text_of(panel(@inside)), "typed in a panel"
    assert_equal 1, forms_of(@inside)
    # The section around the panel was reconciled and not left as it was: its tile is the answer's, another clean panel
    # is the answer's, and the block the colleague added has a tile and a panel.
    assert_not same?("__tile", card(@inside))
    assert_not same?("__other", panel(@other))
    assert_selector "#section-#{@section.id}-lanes #content_block_#{added.id}"
    assert_selector panel(added), visible: :all
    assert_equal [], duplicate_ids
  end

  test "the open panel of a section is open after a merge and its tile says so; a collapsed card stays collapsed" do
    find("#{card(@inside)} .admin-block-tile__face").click
    assert_selector panel(@inside), visible: :visible
    find("#{card(@first)} button[aria-controls='block-#{@first.id}-body']").click
    assert_selector "#{card(@first)} [data-block-body].hidden", visible: :all

    merge_list

    assert_selector panel(@inside), visible: :visible
    assert_equal "true", find("#{card(@inside)} .admin-block-tile__face")["aria-expanded"]
    assert_selector "#{card(@first)} [data-block-body].hidden", visible: :all
    assert_equal "false", find("#{card(@first)} button[aria-controls='block-#{@first.id}-body']")["aria-expanded"]
    assert_no_selector "#{card(@second)} [data-block-body].hidden", visible: :all
  end

  test "a section's own unsaved setting stays while its lanes take a colleague's new tile" do
    form = "#section-#{@section.id}-form"
    raise_debounce(form)
    find("#{form} #block-#{@section.id}-background").find("option[value=strong]").select_option
    keep(form, "__a")
    added = colleague { add_block(section_id: @section.id, section_column: 2) }

    result = merge_list

    assert_equal [ "section-#{@section.id}-form" ], result["kept"]
    assert same?("__a", form)
    assert_equal "strong", find("#{form} #block-#{@section.id}-background").value
    assert_selector "#section-#{@section.id}-lanes [data-column='2'] [data-block-id='#{added.id}']"
    assert_selector "#block-#{added.id}-panel", visible: :all
    assert_equal 1, page.evaluate_script("document.querySelectorAll('#section-#{@section.id}-form').length")
  end

  test "two cards that both hold unsaved text keep both texts when their order changed" do
    type_unsaved(@first, "first words")
    type_unsaved(@second, "second words")
    keep(card(@first), "__a")
    keep(card(@second), "__b")
    colleague { assert ContentBlocks::Reorder.call(@page, [ @second.id, @first.id, @section.id ]).ok? }

    result = merge_list

    assert_equal [ "content_block_#{@first.id}", "content_block_#{@second.id}" ].sort, result["kept"].sort
    assert same?("__a", card(@first))
    assert same?("__b", card(@second))
    assert_equal server_order, list_order
    assert_selector "#{card(@first)} .ProseMirror", text: "first words"
    assert_selector "#{card(@second)} .ProseMirror", text: "second words"
  end

  test "merging the same answer twice changes nothing the second time" do
    type_unsaved(@first, "half a sentence")
    keep(card(@first), "__a")
    colleague { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }

    # The answer is parsed once: each merge gets its own copy of it, since a merge moves what it draws out of it.
    first, second = run_merge(blocks_path, <<~JS)
      const unsaved = window.__unsaved
      const once = () => {
        const result = merge.mergeList(list, fresh.cloneNode(true), { unsaved })
        return { ids: Array.from(list.children).map((each) => each.id), kept: result.kept.map((each) => each.id), gone: result.gone.length, kept_html: result.kept.map((each) => each.outerHTML) }
      }
      done([ once(), once() ])
    JS

    assert_equal first, second
    assert same?("__a", card(@first))
    assert_equal list_order.uniq, list_order
    assert_equal server_order, list_order
  end

  # Scrolls `anchor` to the top of the screen, has a colleague put three blocks above everything, merges, and
  # reads the anchor's place again once the redrawn cards have mounted their editors (they are empty `div`s until
  # then and grow by a field's height each): the block being read has not moved.
  def assert_stays_put(anchor, focus: nil)
    8.times { add_block }
    open_editor
    page.execute_script("document.querySelector(#{anchor.to_json}).scrollIntoView({ block: 'start' })")
    find(focus).click if focus
    added = colleague { 3.times.map { add_block } }
    colleague { assert ContentBlocks::Reorder.call(@page, added.map(&:id) + (server_order - added.map(&:id))).ok? }
    before = page.evaluate_script("document.querySelector(#{anchor.to_json}).getBoundingClientRect().top")

    merge_list

    assert_eventually(message: "the redrawn editors never mounted") do
      page.evaluate_script("document.querySelectorAll('#content-blocks-list .ProseMirror').length") >= server_order.size - 1
    end
    await_frames
    assert_eventually(message: "the block being read moved: it was at #{before}") do
      (page.evaluate_script("document.querySelector(#{anchor.to_json}).getBoundingClientRect().top") - before).abs < 2
    end
    assert_equal server_order, list_order
  end

  test "the block being read does not move on screen when a card is added above it" do
    assert_stays_put(card(@section))
  end

  test "the block with the focus does not move on screen when cards are added above it" do
    assert_stays_put(card(@second), focus: "#{card(@second)} .ProseMirror")
  end

  test "one block's answer replaces its card and nothing else; a card holding unsaved text is kept; an answer of the other shape is reported missing" do
    keep(card(@first), "__a")
    keep(card(@second), "__b")
    colleague { assert ContentBlocks::Save.call(@second, translations: { "en" => { body: rich_doc("Theirs") } }).ok? }

    result = merge_units(blocks_path(@second))

    assert_equal [ "content_block_#{@second.id}" ], result["replaced"]
    assert_equal [], result["kept"]
    assert_not result["missing"]
    assert same?("__a", card(@first))
    assert_not same?("__b", card(@second))
    assert_selector "#{card(@second)} .ProseMirror", text: "Theirs"

    type_unsaved(@first, "my words")
    colleague { assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Theirs again") } }).ok? }
    result = merge_units(blocks_path(@first))

    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert_equal [], result["replaced"]
    assert same?("__a", card(@first))
    assert_selector "#{card(@first)} .ProseMirror", text: "my words"

    # The block with the unsaved text moved into a section: it is displaced, and nothing of it is drawn.
    move_into_section(@first, @section)
    result = merge_units(blocks_path(@first))

    assert_equal [ "content_block_#{@first.id}" ], result["moved"]
    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert_equal [], result["replaced"]
    assert_not result["missing"]
    assert_equal 1, forms_of(@first)

    # A clean card whose block moved into a section is another shape: the caller fetches the list.
    move_into_section(@second, @section)
    before = page.evaluate_script("document.getElementById('content-blocks-list').innerHTML")
    keep(card(@second), "__b")
    result = merge_units(blocks_path(@second))

    assert result["missing"]
    assert_equal [], result["replaced"]
    assert same?("__b", card(@second))
    assert_equal before, page.evaluate_script("document.getElementById('content-blocks-list').innerHTML")
  end

  test "the focus is on the same field after its card was replaced" do
    find("#{card(@first)} .ProseMirror").click
    page.execute_script("window.__old = document.activeElement")
    assert page.evaluate_script("window.__old.closest(#{card(@first).to_json}) !== null")

    merge_list

    assert_eventually(message: "the focus never came back to the replaced card's field") do
      page.evaluate_script("document.activeElement !== window.__old && document.activeElement.isConnected && document.activeElement.closest(#{card(@first).to_json}) !== null && document.activeElement.isContentEditable")
    end
  end

  test "a part that shows an alert is not replaced" do
    post = create_post(title: "Notes")
    open_editor "/cs-studio/posts/#{post.id}"
    page.execute_script("document.getElementById('editor-notice').innerHTML = '<p role=\"alert\">Changed elsewhere</p>'")
    keep("#editor-notice [role=alert]", "__a")

    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const fresh = document.createElement("div")
        fresh.innerHTML = '<div id="editor-notice"></div>'
        const result = merge.mergeUnits(document.body, fresh, { unsaved: window.__unsaved })
        done({ kept: result.kept.map((each) => each.id), replaced: result.replaced.length, missing: result.missing })
      })
    JS

    assert_equal [ "editor-notice" ], result["kept"]
    assert_equal 0, result["replaced"]
    assert_not result["missing"]
    assert same?("__a", "#editor-notice [role=alert]")

    # An alert with nothing in it (every rich-text field renders one) is not a notice: the part is replaced.
    page.execute_script("document.getElementById('editor-notice').innerHTML = '<p role=\"alert\"></p>'")
    emptied = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const fresh = document.createElement("div")
        fresh.innerHTML = '<div id="editor-notice"></div>'
        const result = merge.mergeUnits(document.body, fresh, { unsaved: window.__unsaved })
        done({ replaced: result.replaced.length, kept: result.kept.length })
      })
    JS
    assert_equal({ "replaced" => 1, "kept" => 0 }, emptied)
  end

  test "a kept card whose block was moved into a section stays where it is, is not gone, and the block has one form" do
    type_unsaved(@first, "my words")
    keep(card(@first), "__a")
    before = page.evaluate_script("document.querySelector(#{card(@first).to_json}).nextElementSibling.id")
    move_into_section(@first, @section)

    result = merge_list

    assert_equal [ "content_block_#{@first.id}" ], result["moved"]
    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert_equal [], result["gone"]
    assert same?("__a", card(@first))
    assert_equal "content-blocks-list", page.evaluate_script("document.querySelector(#{card(@first).to_json}).parentElement.id")
    assert_equal before, page.evaluate_script("document.querySelector(#{card(@first).to_json}).nextElementSibling.id")
    assert_nil find(card(@first), visible: :all)["data-editing-gone"]
    assert_equal 1, forms_of(@first)
    assert_equal [], duplicate_ids
    assert_no_selector "#section-#{@section.id}-lanes #content_block_#{@first.id}"
    assert_selector "#{card(@first)} .ProseMirror", text: "my words"
  end

  test "a kept panel whose block was moved out to the top level stays, is shown, is not gone, and the block has one form" do
    hidden_panel_with(@inside, "panel words")
    keep(panel(@inside), "__a")
    colleague do
      assert ContentBlocks::Reorder.call(@page, server_order + [ @inside.id ], moved_from: { @inside.id => { section_id: @section.id, column: 1 } }).ok?
    end

    result = merge_list

    assert_equal [ "block-#{@inside.id}-panel" ], result["moved"]
    assert_equal [ "block-#{@inside.id}-panel" ], result["kept"]
    assert_equal [], result["gone"]
    assert same?("__a", panel(@inside))
    assert_equal "panels", page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).parentElement.id.replace(/section-\\d+-/, '')")
    # Its tile is gone from the lanes: a hidden form with nothing leading to it is shown.
    assert_not page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).hidden")
    assert_equal 1, forms_of(@inside)
    assert_no_selector "#content-blocks-list > #content_block_#{@inside.id}"
    assert_equal [], duplicate_ids
    assert_includes text_of(panel(@inside)), "panel words"
  end

  test "a kept panel whose block was moved to another section stays, is not gone, and the block has one form and one way in" do
    section2 = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    open_editor
    hidden_panel_with(@inside, "panel words")
    keep(panel(@inside), "__a")
    colleague do
      assert ContentBlocks::Reorder.call(@page, [ @inside.id ], section: section2.id, column: 1, moved_from: { @inside.id => { section_id: @section.id, column: 1 } }).ok?
    end

    result = merge_list

    assert_equal [ "block-#{@inside.id}-panel" ], result["moved"]
    assert_equal [], result["gone"]
    assert same?("__a", panel(@inside))
    assert_equal "section-#{@section.id}-panels", page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).parentElement.id")
    assert_equal 1, forms_of(@inside)
    assert_no_selector "#section-#{section2.id}-lanes #content_block_#{@inside.id}"
    assert_equal [], duplicate_ids
    assert_includes text_of(panel(@inside)), "panel words"

    # Once the form is no longer unsaved the next list takes it to its place, with no notice.
    page.execute_script("window.__unsaved = () => false")
    merge_list
    assert_selector "#section-#{section2.id}-lanes #content_block_#{@inside.id}"
    assert_equal 1, forms_of(@inside)
    assert_equal [], duplicate_ids
  end

  test "a gone card keeps its place among the cards that are redrawn, and two gone cards keep their order" do
    third = add_block
    @page.content_blocks.reload
    open_editor
    type_unsaved(@second, "second words")
    type_unsaved(third, "third words")
    colleague do
      assert ContentBlocks::Destroy.call(ContentBlock.find(@second.id)).ok?
      assert ContentBlocks::Destroy.call(ContentBlock.find(third.id)).ok?
    end

    result = merge_list

    assert_equal [ "content_block_#{@second.id}", "content_block_#{third.id}" ], result["gone"]
    assert_equal [ @first.id, @second.id, @section.id, third.id ], list_order
  end

  test "a gone card stays after its neighbour and before the next, whatever was redrawn around it" do
    third = add_block
    open_editor
    type_unsaved(@second, "second words")
    colleague { assert ContentBlocks::Destroy.call(ContentBlock.find(@second.id)).ok? }

    merge_list

    assert_equal [ @first.id, @second.id, @section.id, third.id ], list_order
  end

  test "a hidden panel whose block was deleted is shown, and reported gone" do
    hidden_panel_with(@inside, "panel words")
    keep(panel(@inside), "__a")
    colleague { assert ContentBlocks::Destroy.call(ContentBlock.find(@inside.id)).ok? }

    result = merge_list

    assert_equal [ "block-#{@inside.id}-panel" ], result["gone"]
    assert_equal [], result["moved"]
    assert same?("__a", panel(@inside))
    assert_equal "true", find(panel(@inside), visible: :all)["data-editing-gone"]
    assert_not page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).hidden")
    assert_selector panel(@inside), visible: :visible
  end

  test "one kept card while the others are reordered around it is never taken out of the document" do
    type_unsaved(@second, "my words")
    watch(card(@second))
    keep("#{card(@second)} .ProseMirror", "__pm")
    colleague { assert ContentBlocks::Reorder.call(@page, [ @section.id, @second.id, @first.id ]).ok? }

    merge_list

    assert_not taken_out?
    assert_equal [ @section.id, @second.id, @first.id ], list_order
    assert same?("__pm", "#{card(@second)} .ProseMirror")
  end

  test "when two kept cards change places the one with the focus is not the one moved, and it still takes typing" do
    type_unsaved(@second, "second words")
    type_unsaved(@first, "first words")  # the focus ends in the first card
    watch(card(@first))
    colleague { assert ContentBlocks::Reorder.call(@page, [ @second.id, @first.id, @section.id ]).ok? }

    merge_list

    assert_not taken_out?
    assert_equal server_order, list_order
    assert page.evaluate_script("document.activeElement.closest(#{card(@first).to_json}) !== null")
    page.driver.browser.keyboard.type(" and more")
    assert_selector "#{card(@first)} .ProseMirror", text: "first words and more"
    assert_selector "#{card(@second)} .ProseMirror", text: "second words"
  end

  test "when two kept cards change places and the focus is in the other one, that one is not moved either" do
    type_unsaved(@first, "first words")
    type_unsaved(@second, "second words")  # the focus ends in the second card
    watch(card(@second))
    colleague { assert ContentBlocks::Reorder.call(@page, [ @second.id, @first.id, @section.id ]).ok? }

    merge_list

    assert_not taken_out?
    assert_equal server_order, list_order
    assert page.evaluate_script("document.activeElement.closest(#{card(@second).to_json}) !== null")
    page.driver.browser.keyboard.type(" and more")
    assert_selector "#{card(@second)} .ProseMirror", text: "second words and more"
  end

  test "a clean text field that has the focus is replaced, and the focus and the selection come back to the same field" do
    page.execute_script(<<~JS)
      document.getElementById("content-blocks-list").insertAdjacentHTML("afterend", '<div id="fx"><div id="fx-box"><textarea id="fx-text">hello world</textarea></div></div>')
      const text = document.getElementById("fx-text")
      text.focus()
      text.setSelectionRange(2, 7)
      window.__old = text
    JS

    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const fresh = document.createElement("div")
        fresh.innerHTML = '<div id="fx-box"><textarea id="fx-text">hello world</textarea></div>'
        merge.mergeUnits(document.getElementById("fx"), fresh, { unsaved: window.__unsaved })
        done(true)
      })
    JS

    assert page.evaluate_script("document.activeElement !== window.__old && document.activeElement.id === 'fx-text'")
    assert_equal [ 2, 7 ], page.evaluate_script("[ document.activeElement.selectionStart, document.activeElement.selectionEnd ]")
  end

  test "a focus that waits for a field to mount is not given to it once the person has gone somewhere else" do
    find("#{card(@first)} .ProseMirror").click
    elsewhere = "#{card(@second)} button[aria-controls='block-#{@second.id}-body']"

    page.evaluate_async_script(<<~JS, elsewhere)
      const [ elsewhere, done ] = arguments
      window.__merge.then((merge) => window.__fresh(#{blocks_path.to_json})).then((fresh) => {
        window.__merge.then((merge) => {
          const list = document.getElementById("content-blocks-list")
          merge.mergeList(list, fresh, { unsaved: window.__unsaved })
          // The editor of the new card has not mounted yet: the person focuses something else first.
          document.querySelector(elsewhere).focus()
          done(true)
        })
      })
    JS

    assert_selector "#{card(@first)} .ProseMirror"
    await_frames
    assert page.evaluate_script("document.activeElement === document.querySelector(#{elsewhere.to_json})")

    # And a click on something that takes no focus (the active element is <body> then) is a person moving on too.
    find("#{card(@first)} .ProseMirror").click
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__fresh(#{blocks_path.to_json}).then((fresh) => window.__merge.then((merge) => {
        merge.mergeList(document.getElementById("content-blocks-list"), fresh, { unsaved: window.__unsaved })
        document.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
        done(true)
      }))
    JS
    assert_selector "#{card(@first)} .ProseMirror"
    await_frames
    assert page.evaluate_script("document.activeElement === document.body")
  end

  test "a part that holds a kept unit is not replaced and is reported missing, so the caller fetches the list" do
    hidden_panel_with(@inside, "panel words")
    keep(panel(@inside), "__a")
    keep(card(@first), "__f")

    result = merge_units(blocks_path)

    assert result["missing"]
    assert_not_includes result["replaced"], "content_block_#{@section.id}"
    assert_includes result["replaced"], "content_block_#{@first.id}"
    assert same?("__a", panel(@inside))
    assert_not same?("__f", card(@first))
  end

  test "a unit that is marked gone loses the mark when the answer has it again; a unit without an id that holds text is kept" do
    keep(card(@first), "__a")
    page.execute_script("document.querySelector(#{card(@first).to_json}).dataset.editingGone = 'true'")
    type_unsaved(@first, "my words")

    merge_list

    assert_nil find(card(@first))["data-editing-gone"]

    kept = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      window.__merge.then((merge) => {
        const box = document.createElement("div")
        box.innerHTML = '<form data-editing-unit id="x"></form><form data-editing-unit></form><p id="p">old</p>'
        const loose = box.children[1]
        const fresh = document.createElement("div")
        fresh.innerHTML = '<form data-editing-unit id="x"></form><p id="p">new</p>'
        const result = merge.mergeList(box, fresh, { unsaved: () => true })
        done({ kept: result.kept.includes(loose), connected: loose.parentElement === box, text: box.querySelector("#p").textContent })
      })
    JS
    assert kept["kept"]
    assert kept["connected"]
    assert_equal "new", kept["text"]
  end

  test "a failed save is unsaved: the panel closed through the tile after it keeps its text" do
    find("#{card(@inside)} .admin-block-tile__face").click
    assert_selector panel(@inside), visible: :visible
    page.execute_script(<<~JS)
      const real = window.fetch
      window.fetch = (input, init) => {
        const url = typeof input === "string" ? input : input.url
        if (url.includes("/content_blocks/#{@inside.id}") && (init?.method || "GET").toUpperCase() !== "GET") return Promise.reject(new TypeError("offline"))
        return real(input, init)
      }
    JS
    field = find("#{panel(@inside)} .ProseMirror")
    field.click
    field.send_keys("typed while offline")
    find("#{card(@inside)} .admin-block-tile__face").click
    assert_eventually(message: "the panel never closed") { page.evaluate_script("document.querySelector(#{panel(@inside).to_json}).hidden") }
    await_frames
    keep(panel(@inside), "__a")

    result = merge_list

    assert_equal [ "block-#{@inside.id}-panel" ], result["kept"]
    assert same?("__a", panel(@inside))
    assert_includes text_of(panel(@inside)), "typed while offline"
  end

  # What scrolls the list, found the way the module finds it.
  SCROLLER_JS = <<~JS.freeze
    (() => {
      for (let each = document.getElementById("content-blocks-list").parentElement; each; each = each.parentElement) {
        const overflow = getComputedStyle(each).overflowY
        if ((overflow === "auto" || overflow === "scroll") && each.scrollHeight > each.clientHeight) return each
      }
      return document.scrollingElement
    })()
  JS

  def scroll_top = page.evaluate_script("#{SCROLLER_JS}.scrollTop")

  def prepare_scroll
    8.times { add_block }
    open_editor
    page.execute_script("document.querySelector(#{card(@section).to_json}).scrollIntoView({ block: 'start' })")
    added = colleague { 3.times.map { add_block } }
    colleague { assert ContentBlocks::Reorder.call(@page, added.map(&:id) + (server_order - added.map(&:id))).ok? }
  end

  test "a one-block answer displaces nothing, whatever the root it is merged into" do
    type_unsaved(@first, "my words")
    hidden_panel_with(@inside, "panel words")
    keep(card(@first), "__a")
    keep(panel(@inside), "__p")
    keep(card(@inside), "__tile")
    colleague do
      assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Theirs") } }).ok?
      assert ContentBlocks::Save.call(ContentBlock.find(@inside.id), translations: { "en" => { body: rich_doc("Theirs too") } }).ok?
    end

    result = merge_units(blocks_path(@first), "editing")

    assert_equal [], result["moved"]
    assert_equal [ "content_block_#{@first.id}" ], result["kept"]
    assert_not result["missing"]
    assert same?("__a", card(@first))
    assert_equal 1, forms_of(@first)

    result = merge_units(blocks_path(@inside), "editing")

    assert_equal [], result["moved"]
    assert_equal [ "block-#{@inside.id}-panel" ], result["kept"]
    assert_equal [ "content_block_#{@inside.id}" ], result["replaced"]
    assert same?("__p", panel(@inside))
    assert_not same?("__tile", card(@inside))
    assert_equal 1, forms_of(@inside)
  end

  test "a panel shown because its tile is gone stays shown when another tile is pressed, and closing the other leaves it" do
    @other = add_block(section_id: @section.id, section_column: 2)
    open_editor
    hidden_panel_with(@inside, "panel words")
    colleague { assert ContentBlocks::Destroy.call(ContentBlock.find(@inside.id)).ok? }
    merge_list
    assert_selector panel(@inside), visible: :visible

    find("#{card(@other)} .admin-block-tile__face").click

    assert_selector panel(@other), visible: :visible
    assert_selector panel(@inside), visible: :visible
    assert_includes text_of(panel(@inside)), "panel words"

    find("#{card(@other)} .admin-block-tile__face").click

    assert_no_selector panel(@other), visible: :visible
    assert_selector panel(@inside), visible: :visible

    # Its own Close button closes it, and only it.
    find("#{card(@other)} .admin-block-tile__face").click
    assert_selector panel(@other), visible: :visible
    within(panel(@inside)) { click_button "Close" }
    assert_no_selector panel(@inside), visible: :visible
    assert_selector panel(@other), visible: :visible
  end

  test "a scroll made by anything else while the correction runs is not undone" do
    prepare_scroll
    merge_list
    page.execute_script("#{SCROLLER_JS}.scrollTop += 300")
    set = scroll_top
    await_frames
    await_frames

    assert_in_delta set, scroll_top, 1
  end

  test "two merges in a row leave one correction, and the block ends where the second found it" do
    prepare_scroll
    result = run_merge(blocks_path, <<~JS)
      const scroller = #{SCROLLER_JS}
      const card = () => document.getElementById(#{"content_block_#{@section.id}".to_json})
      const unsaved = window.__unsaved
      merge.anchored(list, () => merge.mergeList(list, fresh.cloneNode(true), { unsaved }))
      // A little up, so the section's card is still the first one wholly in view for the second merge.
      scroller.scrollTop -= 30
      const before = card().getBoundingClientRect().top
      merge.anchored(list, () => merge.mergeList(list, fresh.cloneNode(true), { unsaved }))
      const samples = []
      let frames = 0
      const sample = () => {
        samples.push(card().getBoundingClientRect().top - before)
        if (++frames < 40) requestAnimationFrame(sample); else done(samples)
      }
      requestAnimationFrame(sample)
    JS

    assert result.all? { |off| off.abs < 2 }, "the block moved against the second merge's place: #{result.map(&:round)}"
  end
end
