require "application_system_test_case"

# The publish dialog's button stays where it is when the overview arrives: a
# person aims at "Publish changes" as the dialog opens, and the answer used to
# grow the dialog and move the button down 46px, under or past the pointer, and
# with a long overview onto another control. Measured, with the answer held back
# so that "before" is really before; the dialog's height is what is fixed
# (`Admin::Ui::DialogComponent`'s `steady:`), and what is longer scrolls inside.
class Admin::PublishDialogSteadySystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @live = create_page(title: "Live page") }
    sign_in_via_form(users(:one))
  end

  def retitle
    Current.set(actor: users(:one)) { assert Pages::Save.call(@live, translations: { "en" => { title: "Live page, retitled" } }).ok? }
  end

  def add_blocks(count)
    Current.set(actor: users(:one)) do
      count.times do |index|
        result = ContentBlocks::Save.call(ContentBlock.new(owner: @live), attributes: { block_type: "rich_text" },
          translations: { "en" => { body: rich_doc("Paragraph #{index}") } })
        assert result.ok?, result.errors.to_sentence
      end
    end
  end

  # Only the overview's own request is held; every other goes to the real fetch.
  def open_dialog_with_the_answer_held
    visit admin_page_path(@live)
    await_admin_controllers
    page.execute_script(<<~JS)
      window.__realFetch = window.fetch
      window.fetch = function (url, options) {
        if (!/\\/changes(\\?|$)/.test(String(url))) return window.__realFetch(url, options)
        return new Promise((resolve) => { window.__releaseOverview = () => resolve(window.__realFetch(url, options)) })
      }
    JS
    press "Publish changes…"
    assert_selector "dialog[open]"
    await_js("typeof window.__releaseOverview === 'function'")
    assert_no_selector "dialog[open] [data-publishing-overview]"
  end

  def measure
    page.evaluate_script(<<~JS)
      (() => {
        const dialog = document.querySelector("dialog[open]")
        const button = dialog.querySelector("footer button[form]").getBoundingClientRect()
        const box = dialog.getBoundingClientRect()
        const body = dialog.querySelector(".admin-dialog__body")
        return { button: [button.left, button.top, button.width, button.height], dialog: [box.top, box.bottom],
                 bodyScrolls: body.scrollHeight > body.clientHeight + 1, windowHeight: window.innerHeight,
                 topOfElementAtButton: document.elementFromPoint(button.left + button.width / 2, button.top + button.height / 2)?.closest("button")?.textContent?.trim() }
      })()
    JS
  end

  def assert_button_stays(long:)
    open_dialog_with_the_answer_held
    before = measure

    page.execute_script("window.__releaseOverview()")
    assert_selector "dialog[open] [data-publishing-overview]"
    await_frames
    after = measure

    before["button"].zip(after["button"]).each { |was, now| assert_in_delta was, now, 0.5, "the button moved: #{before["button"]} to #{after["button"]}" }
    assert_operator after["dialog"].last, :<=, after["windowHeight"], "the dialog stays on the screen"
    assert_equal "Publish changes", after["topOfElementAtButton"], "the button itself is what is at that point"
    assert_equal long, after["bodyScrolls"], "a long overview scrolls inside, a short one has no reason to"
    page.execute_script("window.fetch = window.__realFetch")
  end

  test "with a one-row overview the button does not move when the overview arrives" do
    retitle
    assert_button_stays(long: false)
  end

  test "with a long overview the button does not move, and the overview scrolls inside the dialog" do
    add_blocks(30)
    assert_button_stays(long: true)
    within("dialog[open]") { assert_selector "[data-change]", minimum: 30, visible: :all }
  end

  test "at a phone's width the button does not move, one row or long" do
    page.driver.resize(390, 800)
    retitle
    assert_button_stays(long: false)
    page.execute_script("document.querySelector('dialog[open]').close()")
    add_blocks(30)
    assert_button_stays(long: true)
  ensure
    page.driver.resize(1400, 1400)
  end

  test "the scheduled-time row the answer shows does not move the button either" do
    retitle
    Current.set(actor: users(:one)) { assert Publishing::PublishChanges.call(@live.reload, at: 2.days.from_now).ok? }
    Current.set(actor: users(:one)) { assert Pages::Save.call(@live.reload, translations: { "en" => { title: "Retitled again" } }).ok? }
    open_dialog_with_the_answer_held
    # The page view drew the row already; hidden by hand, it is what a change
    # scheduled by a colleague since the page was drawn looks like.
    page.execute_script("document.querySelector('dialog[open] [data-admin--editor--publish-dialog-target=keptRow]').hidden = true")
    before = measure
    page.execute_script("window.__releaseOverview()")
    assert_selector "dialog[open] [data-admin--editor--publish-dialog-target=keptRow]", visible: true
    await_frames
    assert_equal before["button"], measure["button"]
    page.execute_script("window.fetch = window.__realFetch")
  end
end
