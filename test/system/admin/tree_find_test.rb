require "application_system_test_case"

# The page tree's find field in a real browser (`Admin::Ui::TreeFindComponent`,
# `admin--tree--find`, `tree/find.js`): typing narrows the tree to the pages
# that match and their ancestors, marks the matched text and opens the
# branches that hold a match without writing the open set; the count is said
# once the typing stops; the tree does not move while narrowed; the keys of
# a find; and nothing of a find is kept in Turbo's snapshot. `find.js`'
# matching is one module test here, imported in the browser from the editor,
# since the project has no JavaScript test runner.
class Admin::TreeFindSystemTest < ApplicationSystemTestCase
  FIELD = "#tree-list-find".freeze
  STATUS = "#tree [role=search] [role=status]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @alpha = create_page(title: "Alpha")
    @beta = create_page(title: "Beta")
    Current.set(actor: users(:one)) { @translations = create_page(title: "Translations", parent: @alpha) }
  end

  def children_hidden?(record) = page.evaluate_script("document.getElementById('tree-children-#{record.id}').hidden")

  def cookie = page.evaluate_script("document.cookie").to_s[/(?:^|; )cs_tree_open=([^;]*)/, 1].to_s

  def field_focused? = page.evaluate_script("document.activeElement?.id") == FIELD.delete_prefix("#")

  def type_in_field(text) = find(FIELD).send_keys(text)

  test "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds" do
    visit_editor(@beta)
    assert children_hidden?(@alpha), "Alpha's branch is folded by default"
    before = cookie

    type_in_field("trans")
    assert_selector "#tree-row-#{@translations.id} a mark", text: "Trans", exact_text: true
    assert_selector "#tree-row-#{@translations.id} a", text: "Translations", exact_text: true
    assert_selector "#tree-row-#{@alpha.id}"
    assert_selector "#tree-row-#{root_page.id}"
    assert_no_selector "#tree-row-#{@beta.id}"
    assert_not children_hidden?(@alpha), "the branch holding the match is open while the find is on"
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=true]"
    assert_selector "li[data-page-id='#{@alpha.id}'][data-filter-open]"
    assert_selector STATUS, text: "1 page matches"
    assert_selector "#{STATUS} span", text: "1", exact_text: true
    assert_equal before, cookie, "the find's opens are not written to the open set"
    assert_selector "[role=search] kbd", visible: :hidden
    assert_selector "[role=search] button[aria-label=Clear]"

    page.send_keys(:escape)
    assert_no_selector "#tree mark"
    assert_selector "#tree-row-#{@beta.id}"
    assert children_hidden?(@alpha), "Escape folds the branch again, as the person had it"
    assert_selector "#tree-row-#{@alpha.id} > .admin-tree-row__disclosure[aria-expanded=false]", visible: :all
    assert_no_selector "#tree [data-filter-open], #tree [data-filter-hidden], #tree [data-filter-match]", visible: :all
    assert_equal "", find(FIELD).value
    assert field_focused?, "the focus stays in the field"
    assert_equal "", find(STATUS, visible: :all).text(:all)
    assert_selector "[role=search] kbd", text: "/"
    assert_equal before, cookie
  end

  test "no match says No pages match, and no tree is shown" do
    visit_editor(@beta)
    type_in_field("zzz")
    assert_selector STATUS, text: "No pages match"
    assert_no_selector "#tree-list [data-tree-row]"
    assert_selector "#tree-list [data-tree-row]", visible: :hidden, minimum: 4

    find("[role=search] button[aria-label=Clear]").click
    assert_selector "#tree-row-#{@beta.id}"
    assert field_focused?, "Clear leaves the focus in the field"
    assert_equal "", find(STATUS, visible: :all).text(:all)
  end

  test "drag is off while filtered and the line says why" do
    visit_editor(@beta)
    handle = "#tree-row-#{@alpha.id} .admin-tree-node__handle"
    assert_selector handle, visible: :all
    assert_not_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{handle.to_json})).display")
    sortables_disabled = "window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('tree'), 'admin--pages--tree').sortables.map((sortable) => sortable.option('disabled'))"
    assert_equal [ false ], page.evaluate_script(sortables_disabled).uniq

    type_in_field("a")
    assert_selector "#tree-list[data-filtered]"
    assert_no_selector "#tree .admin-tree-node__handle"
    assert_empty page.evaluate_script("Array.from(document.querySelectorAll('#tree .admin-tree-node__handle')).filter((each) => getComputedStyle(each).display !== 'none')"), "a handle is drawn while the tree is narrowed"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{handle.to_json})).display")
    assert_equal [ true ], page.evaluate_script(sortables_disabled).uniq
    assert_selector STATUS, text: "Clear the search to move pages"
    assert_selector "#tree-row-#{@alpha.id} .admin-tree-row__add", visible: :all
    assert_not_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('#tree-row-#{@alpha.id} .admin-tree-row__add')).display")

    # Space on a row's link, and on its handle's own keydown, picks nothing up.
    page.execute_script("document.getElementById('tree-link-#{@alpha.id}').focus()")
    page.driver.browser.keyboard.type(:space)
    page.execute_script("document.querySelector(#{handle.to_json}).dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }))")
    await_frames
    assert_no_selector "#tree [data-picked]", visible: :all

    find(FIELD).click
    page.send_keys(:escape)
    assert_no_selector "#tree-list[data-filtered]"
    assert_not_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{handle.to_json})).display")
    assert_equal [ false ], page.evaluate_script(sortables_disabled).uniq
  end

  test "/ focuses the field, Down Arrow reaches the first match, Enter opens it" do
    visit_editor(@alpha)
    page.execute_script("document.activeElement?.blur()")
    page.send_keys("/")
    assert_eventually(message: "/ did not focus the find field") { field_focused? }
    assert_equal "", find(FIELD).value, "the slash that focused the field is not typed into it"

    page.send_keys("beta")
    assert_selector "#tree-row-#{@beta.id} mark", text: "Beta"
    page.send_keys(:down)
    assert_eventually(message: "Down Arrow did not reach the first match") { page.evaluate_script("document.activeElement?.id") == "tree-link-#{@beta.id}" }
    page.send_keys(:up)
    assert_eventually(message: "Up Arrow did not come back to the field") { field_focused? }

    page.send_keys(:enter)
    assert_selector "#content h1", text: "Beta"
    assert_selector "#tree-row-#{@beta.id}.admin-tree-row--selected"
  end

  test "the count is said once, after the typing stops" do
    visit_editor(@beta)
    page.execute_script(<<~JS)
      window.__said = []
      const status = document.querySelector(#{STATUS.to_json})
      new MutationObserver(() => {
        if (window.__said.at(-1) !== status.textContent) window.__said.push(status.textContent)
      }).observe(status, { subtree: true, childList: true, characterData: true })
    JS
    type_in_field("trans")
    assert_selector STATUS, text: "1 page matches"
    sleep 0.4 # sleep: longer than the status line's 300ms timer, to see that no second sentence follows
    assert_equal [ "1 page matches Clear the search to move pages" ], page.evaluate_script("window.__said")
  end

  test "a page saved while the tree is filtered keeps its row filtered and marked" do
    visit_editor(@translations)
    type_in_field("trans")
    assert_selector "#tree-row-#{@translations.id} a mark", text: "Trans"
    assert_no_selector "#tree-row-#{@beta.id}"

    fill_in "Title", with: "Translations guide"
    page.execute_script("document.activeElement.blur()")
    assert_eventually { @translations.reload.title == "Translations guide" }
    assert_selector "#tree-row-#{@translations.id}[data-tree-title='Translations guide'] a mark", text: "Trans"
    assert_selector "#tree-row-#{@translations.id} a", text: "Translations guide", exact_text: true
    assert_no_selector "#tree-row-#{@beta.id}"
    assert_selector "li[data-page-id='#{@beta.id}'][data-filter-hidden]", visible: :hidden
    assert_selector "#tree-list[data-filtered]"
  end

  test "Back after a find shows the whole tree, an empty field and no marks" do
    visit_editor(@beta)
    type_in_field("trans")
    assert_selector "#tree-row-#{@translations.id} mark"
    assert_selector STATUS, text: "1 page matches"

    page.execute_script("Turbo.visit('/cs-studio')")
    assert_current_path "/cs-studio"
    page.go_back
    assert_selector "#tree-row-#{@beta.id}"
    await_admin_controllers
    assert_equal "", find(FIELD).value
    assert_no_selector "#tree mark"
    assert_no_selector "#tree [data-filter-open], #tree [data-filter-hidden], #tree [data-filter-match], #tree-list[data-filtered]", visible: :all
    assert children_hidden?(@alpha), "the person's fold is back"
    assert_equal "", find(STATUS, visible: :all).text(:all)
    assert_selector "[role=search] kbd", text: "/"
    assert_selector "[role=search] button[aria-label=Clear]", visible: :hidden
  end

  test "a slash typed into a field or the rich-text body stays a slash, and Escape in the empty field closes the drawer" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @beta), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello") } }).record
    visit_editor(@beta)

    find_field("Title").click
    find_field("Title").send_keys("/")
    assert_equal "Beta/", find_field("Title").value
    assert_not field_focused?

    body = "#content_block_#{block.id} .ProseMirror"
    find(body).click
    find(body).send_keys("/")
    assert_selector body, text: "/"
    assert_not field_focused?

    at_window(900) do
      # The drawer hides itself 0.2s after it stops being a column (its
      # `visibility` transition).
      await_js "getComputedStyle(document.getElementById('tree-column')).visibility === 'hidden'", message: "the shut drawer never hid"
      page.execute_script("document.activeElement?.blur()")
      page.send_keys("/")
      await_frames
      assert_not field_focused?, "/ focused a field the shut drawer hides"

      find("button[aria-controls='tree-column'][data-admin--shell--drawer-target=trigger]").click
      assert_selector "#tree-column[data-open]"
      find(FIELD).click
      page.send_keys(:escape)
      assert_no_selector "#tree-column[data-open]", visible: :all
    end
  end

  test "a title with markup is marked as text" do
    marked = create_page(title: "<b>Bold</b> & co")
    visit_editor(@beta)
    type_in_field("bold")
    assert_selector "#tree-row-#{marked.id} a mark", text: "Bold", exact_text: true
    assert_selector "#tree-row-#{marked.id} a", text: "<b>Bold</b> & co", exact_text: true
    assert_no_selector "#tree-list b", visible: :all
  end

  def with_module(body)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("tree/find").then((mod) => done((() => { #{body} })())).catch((error) => done({ error: String(error) }))
    JS
  end

  test "matching ignores case and accents, finds a part anywhere, and matches the address only after a slash" do
    visit_editor(@beta)
    result = with_module(<<~JS)
      const box = document.createElement("ul")
      box.innerHTML = '<li data-tree-node><div data-tree-row data-tree-title="Über uns" data-tree-path="/ueber-uns"><span class="admin-tree-row__title"><a data-tree-focus>Über uns</a></span></div></li>' +
        '<li data-tree-node><div data-tree-row data-tree-title="install" data-tree-path="/docs/install"><span class="admin-tree-row__title"><a data-tree-focus>install</a></span></div></li>'
      document.body.append(box)
      const marked = (query) => {
        const out = { count: mod.filterTree(box, query, { locale: "de" }).count, marks: Array.from(box.querySelectorAll("mark"), (mark) => mark.textContent), shown: Array.from(box.children).filter((node) => !node.hidden).length }
        mod.clearFilter(box)
        return out
      }
      const out = {
        uber: mod.normalise("Über uns", "de").includes(mod.normalise("uber", "de")),
        upper: mod.normalise("Über uns", "de").includes(mod.normalise("ÜBER", "de")),
        decomposed: mod.matchesTitle("U\\u0308ber uns", "über", "de"),
        middle: mod.matchesTitle("Über uns", "r u", "de"),
        slashTitle: mod.matchesTitle("install", "/install", "en"),
        slashPath: mod.matchesPath("/docs/install", "/install"),
        noSlashPath: mod.matchesPath("/docs/page", "page"),
        uberFound: marked("uber"),
        installFound: marked("/install"),
        nothing: marked("page"),
        left: box.querySelectorAll("mark, [hidden], [data-filter-hidden], [data-filter-match]").length
      }
      box.remove()
      return out
    JS

    assert_nil result["error"]
    assert result["uber"], "uber finds Über uns"
    assert result["upper"], "ÜBER finds Über uns"
    assert result["decomposed"], "a decomposed Ü matches"
    assert result["middle"], "a part in the middle matches"
    assert_not result["slashTitle"], "a query with a slash does not match a title"
    assert result["slashPath"], "/install matches /docs/install"
    assert_not result["noSlashPath"], "a query without a slash matches no address"
    assert_equal({ "count" => 1, "marks" => [ "Über" ], "shown" => 1 }, result["uberFound"], "uber marks Über")
    assert_equal({ "count" => 1, "marks" => [], "shown" => 1 }, result["installFound"])
    assert_equal({ "count" => 0, "marks" => [], "shown" => 0 }, result["nothing"])
    assert_equal 0, result["left"], "clearFilter takes back everything the find wrote"
  end
end
