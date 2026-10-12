require "application_system_test_case"

# What a live record's header, the page tree, the posts list and the dashboard
# say once its rows have moved on from what is published (drafts plan, task 6).
# The answer to a save carries the header's chip part, so the mark and the
# two buttons it shows appear with the first change and not at the next
# reload. The dialog those buttons open is `drafts_test.rb`'s.
class UnpublishedChangesSystemTest < ApplicationSystemTestCase
  HEADER = "header.admin-editor-header".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @live = create_page(title: "Live page") }
  end

  test "typing in a live page shows the chip, the button and the tree's dot with no reload, and publishing the changes takes them away" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@live)
    await_admin_controllers

    # Both parts are in the header from the start, empty.
    assert_selector "#{HEADER} #publishing-chip", visible: :all
    assert_selector "#{HEADER} #publishing-actions", visible: :all
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    assert_no_button "Publish changes…"
    assert_no_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes]"

    # One value set in one go, then Tab: the field's own blur saves at once.
    title = find_field("Title")
    title.set("Live page, retitled")
    title.send_keys(:tab)

    assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]", text: "Unpublished changes"
    assert_selector "#{HEADER} #publishing-actions button", text: "Publish changes…"
    assert_selector "#{HEADER} #publishing-actions button", text: "Discard changes…"
    assert_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes][aria-label='Unpublished changes']"
    assert @live.reload.unpublished_changes?
    assert_equal "Live page", Publishing.current(@live).snapshot.dig("fields", "title", "en"), "the site still shows what was published"

    press "Publish changes…"
    within("dialog[open]") { press "Publish changes" }

    assert_no_selector "#{HEADER} [data-unpublished-changes]", wait: 10
    assert_no_selector "#{HEADER} #publishing-actions button"
    assert_no_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes]"
    assert_text "Changes published"
    assert_equal "Live page, retitled", Publishing.current(@live.reload).snapshot.dig("fields", "title", "en")
    assert_not @live.unpublished_changes?
  end

  test "the posts list marks a live post with unpublished changes, and the dashboard lists it under Unpublished changes" do
    Current.set(actor: users(:one)) do
      @marked = create_post(title: "Marked post")
      @plain = create_post(title: "Plain post")
      assert Posts::Save.call(@marked, translations: { "en" => { title: "Marked post, retyped" } }).ok?
    end
    sign_in_via_form(users(:one))

    visit admin_posts_path
    assert_selector "tbody tr", text: "Marked post, retyped"
    assert_selector "tbody tr", text: "Plain post"
    assert_selector "tbody tr [data-unpublished-changes]", count: 1
    assert_selector "tbody tr:has(a[href$='/posts/#{@marked.id}']) [data-unpublished-changes]"

    visit admin_root_path
    assert_selector "section[aria-labelledby=dashboard-unpublished-changes] a[href$='/posts/#{@marked.id}']", text: "Marked post, retyped"
    assert_no_selector "section[aria-labelledby=dashboard-unpublished-changes] a[href$='/posts/#{@plain.id}']"
  end

  # -- the press that is not lost (fix round 1, C1) ------------------------------

  LIVE = 8

  # Holds the NEXT request of `verb` whose URL matches `source` before it is
  # sent: it reaches the server only at `send_delayed`. Passes every other
  # request through (the live parts fetch too).
  def delay_next(verb, source)
    page.execute_script(<<~JS, verb, source)
      const [ verb, source ] = arguments
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const method = String(init.method || "GET").toUpperCase()
        if (!spent && method === verb && new RegExp(source).test(url)) {
          spent = true
          const args = arguments
          return new Promise((resolve) => { window.__delayed = () => resolve(real.apply(window, args)) })
        }
        return real.apply(this, arguments)
      }
    JS
  end

  def await_delayed = assert_eventually(wait: LIVE, message: "the delayed request never reached the page's fetch") { page.evaluate_script("typeof window.__delayed === 'function'") }

  def send_delayed = page.execute_script("window.__delayed(); window.__delayed = null")

  test "Publish changes pressed in its dialog while a block's autosave is still out is sent once, after the save, and the copy holds the typed text" do
    page_record = nil
    Current.set(actor: users(:one)) do
      page_record = create_page(title: "Press", published: false)
      @block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "rich_text" }).record
      assert Pages::Save.call(page_record, attributes: { published: true }).ok?
      assert Pages::Save.call(page_record, translations: { "en" => { subtitle: "Marked" } }).ok? # the button is on the page from the start
    end
    sign_in_via_form(users(:one))
    visit admin_page_path(page_record)
    await_notes_live
    assert_selector "#{HEADER} #publishing-actions button", text: "Publish changes…"
    copies = Publishing::Version.of(page_record).count

    delay_next("PATCH", "/content_blocks/#{@block.id}")
    find("#content_block_#{@block.id} .ProseMirror").click
    find("#content_block_#{@block.id} .ProseMirror").send_keys("Z")
    await_delayed

    press "Publish changes…"
    within("dialog[open]") { press "Publish changes" }
    await_frames
    assert_equal copies, Publishing::Version.of(page_record).count, "the press waits for the save that is out"
    send_delayed

    assert_eventually(wait: 10, message: "the publish never arrived") { Publishing::Version.of(page_record).count == copies + 1 }
    assert_equal 1, Audit::Event.where(action: "page.changes_published", subject: page_record).count
    assert_includes Publishing.current(page_record).blocks.sole["body"].to_s, "Z", "the copy holds the typed text"
    assert_no_selector "#{HEADER} [data-unpublished-changes]", wait: 10
    assert_not page_record.reload.unpublished_changes?
  end

  # -- another tab's header (fix round 1, I3) ------------------------------------

  test "a colleague's header learns of a change and of its publication without a reload" do
    dana = users(:two)
    sign_in_via_form(users(:one))
    visit admin_page_path(@live)
    await_notes_live

    using_session(:dana) do
      sign_in_via_form(dana)
      visit admin_page_path(@live)
      await_notes_live
      assert_no_selector "#{HEADER} [data-unpublished-changes]"
      assert_no_button "Publish changes…"
    end

    title = find_field("Title")
    title.set("Retitled by Olga")
    title.send_keys(:tab)
    assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]"

    using_session(:dana) do
      assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]", wait: LIVE
      assert_selector "#{HEADER} #publishing-actions button", text: "Publish changes…", wait: LIVE
      assert_selector "#{HEADER} #publishing-actions button", text: "Discard changes…", wait: LIVE
    end

    assert_writes_settled
    press "Publish changes…"
    within("dialog[open]") { press "Publish changes" }
    assert_no_selector "#{HEADER} [data-unpublished-changes]", wait: 10

    using_session(:dana) do
      assert_no_selector "#{HEADER} [data-unpublished-changes]", wait: LIVE
      assert_no_button "Publish changes…"
    end
  end
end
