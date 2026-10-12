require "application_system_test_case"

# Drafts of live content, in a browser (drafts spec §8): the publish dialog
# with its overview and its time, Discard changes, Cancel scheduled change.
# Two people are two sessions; a visitor is a third that never signs in.
# Nothing here asserts how long anything took, a copy's time is moved by
# writing the row, and a request that must be out while something is pressed
# is HELD (`delay_next`), never raced.
class Admin::DraftsSystemTest < ApplicationSystemTestCase
  HEADER = "header.admin-editor-header".freeze
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    Current.set(actor: @me) do
      @page = create_page(title: "Pricing", published: false)
      @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("As published") } }).record
      assert Pages::Save.call(@page, attributes: { published: true }).ok?
    end
    @address = PublicSite::Urls.new.path_for(@page, "en")
    sign_in_via_form(@me)
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def as_me(&) = Current.set(actor: @me, &)

  def editor = admin_page_path(@page)

  def open_editor
    visit editor
    await_notes_live
  end

  def visitor_sees(text, absent: nil)
    using_session(:visitor) do
      visit @address
      assert_text text
      assert_no_text absent if absent
    end
  end

  # One value set in one go, then Tab: the field's own blur saves at once
  # (as `unpublished_changes_test.rb` types a page's title).
  def retitle(text)
    title = find_field("Title")
    title.set(text)
    title.send_keys(:tab)
  end

  def publish_dialog = "dialog#publish-changes-page-#{@page.id}[open]"

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

  # One key into the block's text while its save is held on the way out.
  def type_while_the_save_is_held
    delay_next("PATCH", "/content_blocks/#{@block.id}")
    find("#content_block_#{@block.id} .ProseMirror").click
    find("#content_block_#{@block.id} .ProseMirror").send_keys("Z")
    await_delayed
  end

  def block_text = @block.reload.body_document(locale: "en").to_markdown.strip

  # -- the dialog ----------------------------------------------------------------

  test "what I save on a live page is not on the site until I publish it through the dialog, which shows what will change" do
    open_editor
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    assert_no_button "Publish changes…"
    assert_no_button "Discard changes…"

    retitle "Pricing, half a sent"
    assert_writes_settled
    assert_text "SAVED · NOT PUBLISHED"
    assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]", text: "Unpublished changes"
    assert_button "Discard changes…"
    visitor_sees "Pricing", absent: "half a sent"

    press "Publish changes…"
    within publish_dialog do
      assert_selector "#publishing-changes [data-changed-fields]", text: "Title"
      assert_selector "#publishing-changes [data-changed-languages]", text: "English"
      assert_no_text "Reading what will change…"
      assert_checked_field "Now"
      press "Publish changes"
    end

    assert_text "Changes published"
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    assert_no_button "Publish changes…"
    visitor_sees "Pricing, half a sent"
  end

  test "the overview is asked again each time the dialog is opened, and says so when there is nothing to publish" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { subtitle: "First edit" } }).ok? }
    open_editor
    press "Publish changes…"
    within(publish_dialog) do
      assert_selector "[data-changed-fields]", text: "Subtitle"
      assert_no_selector "[data-change]"
      press "Cancel"
    end
    assert_no_selector "dialog[open]"

    as_me { assert ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Added elsewhere") } }).ok? }
    press "Publish changes…"
    within(publish_dialog) do
      assert_selector "[data-change=added]", text: "Added elsewhere"
      press "Cancel"
    end

    # Typed and typed back: the mark stays (so the button does), and nothing differs.
    as_me do
      assert ContentBlocks::Destroy.call(@page.content_blocks.reorder(:id).last).ok?
      assert Pages::Save.call(@page.reload, translations: { "en" => { subtitle: "" } }).ok?
    end
    press "Publish changes…"
    within(publish_dialog) do
      assert_text "Nothing to publish. This is the same as what is published."
      assert_no_selector "[data-change], [data-changed-fields]"
    end
  end

  test "the overview is asked through the write queue: opened while a block's save is out, it is read after that save and shows what was typed" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { subtitle: "Marked" } }).ok? }
    open_editor
    type_while_the_save_is_held

    press "Publish changes…"
    within(publish_dialog) do
      assert_text "Reading what will change…"
      await_frames
      assert_no_selector "[data-publishing-overview]"
    end
    send_delayed

    within(publish_dialog) do
      assert_selector "[data-change=changed]", text: "Z", wait: 10
      assert_no_text "Reading what will change…"
    end
    assert_empty Publishing::Version.of(@page).where(number: 2..), "asking published nothing"
  end

  # "Publish changes pressed in its dialog while a block's autosave is still
  # out is sent once, after the save" is `unpublished_changes_test.rb`'s.

  test "changes published at a time are not on the site until that time has come, and the header says when" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Tomorrow's title" } }).ok? }
    open_editor
    press "Publish changes…"
    within publish_dialog do
      assert_selector "[data-changed-fields]", text: "Title"
      choose "At a time"
      press "Publish changes"
    end

    assert_text "Changes scheduled for"
    assert_selector "#{HEADER} #publishing-chip [data-change-scheduled]", text: "Changes scheduled for"
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    visitor_sees "Pricing", absent: "Tomorrow's title"

    Publishing::Version.of(@page).pending.update_all(live_at: 1.minute.ago) # version: none (a test moves a copy's clock)
    visitor_sees "Tomorrow's title"
  end

  test "a time picked in the dialog chooses At a time by itself" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    open_editor
    press "Publish changes…"

    within publish_dialog do
      assert_checked_field "Now"
      find("input[name=published_at]").set(3.days.from_now.strftime("%Y-%m-%dT%H:%M"))
      assert_checked_field "At a time"
    end
  end

  test "with a change scheduled the dialog offers its time first, the menu cancels it after asking, and the rows stay as unpublished changes" do
    as_me do
      assert Pages::Save.call(@page, translations: { "en" => { title: "Scheduled title" } }).ok?
      publish_changes(@page, at: 2.days.from_now)
    end
    open_editor
    press "Publish changes…"
    within(publish_dialog) do
      assert_selector "input[name=when][value=kept]:checked"
      assert_text "At the scheduled time ("
      assert_text "Nothing new to publish. This is the same as the changes scheduled for"
      press "Cancel"
    end

    open_editor_menu
    press "Cancel scheduled change"
    within "dialog[open]" do
      assert_text "They stay in the editor as unpublished changes."
      press "Cancel scheduled change"
    end

    assert_text "Scheduled change cancelled"
    assert_no_selector "#{HEADER} [data-change-scheduled]"
    assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]"
    assert_nil Publishing.pending(@page)
    assert_equal "Scheduled title", Mobility.with_locale(:en) { @page.reload.title }
    visitor_sees "Pricing", absent: "Scheduled title"
  end

  test "Cancel scheduled change pressed while a block's autosave is still out is sent once, after the save" do
    as_me do
      assert Pages::Save.call(@page, translations: { "en" => { title: "Scheduled title" } }).ok?
      publish_changes(@page, at: 2.days.from_now)
    end
    open_editor
    type_while_the_save_is_held

    open_editor_menu
    press "Cancel scheduled change"
    within("dialog[open]") { press "Cancel scheduled change" }
    await_frames
    assert Publishing.pending(@page), "the press waits for the save that is out"
    send_delayed

    assert_text "Scheduled change cancelled", wait: 10
    assert_equal 1, Audit::Event.where(action: "page.scheduled_change_cancelled", subject: @page).count
    assert_nil Publishing.pending(@page)
    assert_includes block_text, "Z", "the save landed first"
  end

  # -- the addresses a publish takes away -------------------------------------------

  test "the dialog names the post that will lose its address when the page is published, links it, and publishing is not refused" do
    post = nil
    as_me do
      list = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
      publish_changes(@page)
      post = create_post(title: "Hello there")
      assert_equal "#{@address}/hello-there", post.reload.full_path("en")
      assert ContentBlocks::Destroy.call(list).ok?
    end
    open_editor
    press "Publish changes…"

    within publish_dialog do
      assert_selector "[data-publishing-lost-addresses]", text: "When this page is published, these lose their address"
      assert_selector "[data-lost-address] a[href='#{admin_post_path(post)}']", text: "Hello there"
      assert_selector "[data-lost-address]", text: "#{@address}/hello-there"
      press "Publish changes"
    end

    assert_text "Changes published"
    assert_nil post.reload.full_path("en")
  end

  # -- discard -----------------------------------------------------------------------

  test "Discard changes puts the page back to what is published, after asking once" do
    as_me do
      assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
      assert ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc("Typed text") } }).ok?
    end
    open_editor
    assert_selector "h1", text: "Typed"

    press "Discard changes…"
    within "dialog[open]" do
      assert_text "Discard the unpublished changes?"
      assert_text "This page goes back to what is published."
      press "Discard changes"
    end

    assert_text "Changes discarded"
    assert_selector "h1", text: "Pricing"
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    assert_no_button "Discard changes…"
    assert_equal "As published", block_text
  end

  test "Discard changes pressed while a block's autosave is still out is sent once, after the save, and what was typed is discarded with the rest" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { subtitle: "Marked" } }).ok? }
    open_editor
    type_while_the_save_is_held

    press "Discard changes…"
    within("dialog[open]") { press "Discard changes" }
    await_frames
    assert_empty Audit::Event.where(action: "page.changes_discarded"), "the press waits for the save that is out"
    send_delayed

    assert_text "Changes discarded", wait: 10
    assert_equal 1, Audit::Event.where(action: "page.changes_discarded", subject: @page).count
    assert Audit::Event.where(action: "block.updated", subject: @block).exists?, "the save landed first"
    assert_equal "As published", block_text
    assert_not @page.reload.unpublished_changes?
  end

  test "while Dana holds a block, the dialog says only what was saved is published, and Discard is refused and says who" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    reserve(@block, @page, @dana, "tab-dana-0001")
    open_editor

    press "Publish changes…"
    within(publish_dialog) do
      assert_selector "[data-publishing-held]", text: "Dana Weiss is editing this page. Only what has been saved is published."
      press "Cancel"
    end

    press "Discard changes…"
    within("dialog[open]") { press "Discard changes" }

    assert_text "Dana Weiss is editing this block"
    assert_equal "Typed", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "two people: what Dana is typing is not published by my publish, and her saved text is" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed by Olga" } }).ok? }
    open_editor

    using_session(:dana) do
      sign_in_via_form(@dana)
      visit editor
      await_notes_live
      delay_next("PATCH", "/content_blocks/#{@block.id}")
      find("#content_block_#{@block.id} .ProseMirror").click
      find("#content_block_#{@block.id} .ProseMirror").send_keys("Z")
      await_delayed
    end

    press "Publish changes…"
    within(publish_dialog) do
      assert_selector "[data-publishing-held]", text: "Dana Weiss is editing this page"
      assert_no_selector "[data-change]"
      press "Publish changes"
    end
    assert_text "Changes published"
    assert_not_includes Publishing.current(@page).blocks.sole["body"].to_s, "Z"

    using_session(:dana) do
      send_delayed
      assert_writes_settled
      assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]", wait: LIVE
    end
    assert_includes block_text, "Z"
    assert @page.reload.unpublished_changes?
  end

  # -- a refusal the dialog shows -----------------------------------------------------

  test "a time in the past comes back in the dialog, open, with the choice and the time that was typed" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    open_editor
    press "Publish changes…"
    within publish_dialog do
      assert_selector "[data-changed-fields]"
      find("input[name=published_at]").set("2001-01-01T09:00")
      press "Publish changes"
    end

    within publish_dialog do
      assert_selector "[role=alert]", text: "Pick a time in the future."
      assert_checked_field "At a time"
      assert_equal "2001-01-01T09:00", find("input[name=published_at]").value
      assert_selector "[data-changed-fields]", text: "Title"
    end
    assert_equal 1, Publishing::Version.of(@page).count
  end

  # -- elsewhere ------------------------------------------------------------------------

  test "the tree and the posts list mark a live record with unpublished changes" do
    as_me do
      post = create_post(title: "A post")
      assert Posts::Save.call(post, translations: { "en" => { title: "A post, edited" } }).ok?
      assert Pages::Save.call(@page, translations: { "en" => { subtitle: "Typed" } }).ok?
    end

    visit admin_pages_path
    assert_selector "li[data-page-id='#{@page.id}'] [data-unpublished-changes]", visible: :all

    visit admin_posts_path
    assert_selector "[data-unpublished-changes]", text: "Unpublished changes"
  end

  # -- what a dialog says about a schedule is asked when it opens, and checked when it is pressed (fix round 1, I1) --

  test "two people: a change Dana scheduled since my page loaded is offered when I open the publish dialog and named when I open the discard dialog" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    open_editor
    assert_no_selector "#{HEADER} [data-change-scheduled]"

    using_session(:dana) do
      sign_in_via_form(@dana)
      visit editor
      await_notes_live
      press "Publish changes…"
      within publish_dialog do
        assert_selector "[data-changed-fields]", text: "Title"
        choose "At a time"
        press "Publish changes"
      end
      assert_text "Changes scheduled for"
    end
    pending = Publishing.pending(@page)
    assert pending

    # My header follows by the live signal; my dialogs were drawn before.
    assert_selector "#{HEADER} #publishing-chip [data-change-scheduled]", wait: LIVE
    assert_equal "", find("#publish-changes-page-#{@page.id} input[name=pending]", visible: :all).value, "drawn when nothing was scheduled"

    press "Publish changes…"
    within publish_dialog do
      assert_text "Nothing new to publish. This is the same as the changes scheduled for"
      assert_selector "input[name=when][value=kept]:checked"
      assert_text "At the scheduled time ("
      assert_equal pending.id.to_s, find("input[name=pending]", visible: :all).value
      press "Cancel"
    end

    as_me { assert Pages::Save.call(@page.reload, translations: { "en" => { subtitle: "One more word" } }).ok? }
    assert_selector "#{HEADER} #publishing-chip [data-discard-changes-offered]", visible: :all, wait: LIVE
    press "Discard changes…"
    within "dialog[open]" do
      assert_selector "[data-discard-withdraws]", text: "are discarded as well."
      assert_equal pending.id.to_s, find("input[name=pending]", visible: :all).value
      press "Cancel"
    end
    assert_equal pending.id, Publishing.pending(@page).id
  end

  test "Now pressed for a schedule that changed after the dialog was filled publishes nothing, and the dialog comes back with the fresh state" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    open_editor
    press "Publish changes…"
    within publish_dialog do
      assert_selector "[data-changed-fields]", text: "Title"
      assert_checked_field "Now"
    end
    # A colleague schedules these changes while my dialog is open.
    as_me { publish_changes(@page, at: 2.days.from_now) }
    pending = Publishing.pending(@page)

    within(publish_dialog) { press "Publish changes" }

    within publish_dialog do
      assert_selector "[role=alert]", text: "The scheduled change was set, moved or cancelled since this was opened. Nothing was done: look again."
      assert_text "At the scheduled time ("
      assert_equal pending.id.to_s, find("input[name=pending]", visible: :all).value
    end
    assert_equal pending.id, Publishing.pending(@page).id
    assert_equal 1, Publishing.current(@page).number
    visitor_sees "Pricing", absent: "Typed"
  end

  test "when the overview cannot be read the dialog says so" do
    as_me { assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok? }
    open_editor
    as_me { assert Trash::Move.call(@page.reload).ok? } # the page goes away elsewhere: the overview's POST answers 404

    press "Publish changes…"

    within publish_dialog do
      assert_text "Couldn’t read what will change. Close this and open it again."
      assert_no_text "Reading what will change…"
      assert_no_selector "[data-publishing-overview]"
    end
  end

  test "Change address… moves a live page at once: the visitor finds it at the new address and is sent on from the old one" do
    open_editor
    assert_no_field "page[slug]", visible: :all
    assert_selector "#page-settings [data-page-address]", text: @address

    press "Change address…"
    within "dialog#page-slug-#{@page.id}[open]" do
      assert_text "The page moves to the new address at once"
      fill_in "Last part of the address", with: "prices"
      press "Change address"
    end

    assert_text "Address changed"
    assert_selector "#page-settings [data-page-address]", text: "/prices"
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    using_session(:visitor) do
      visit "/prices"
      assert_text "As published"
      visit @address
      assert_current_path "/prices"
      assert_text "As published"
    end
  end
end
