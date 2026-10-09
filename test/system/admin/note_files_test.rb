require "application_system_test_case"
require "support/note_files_helper"

# Files on a note in the browser (notes spec D9, §3.6, §4.5 "Motion", §6.3):
# chosen in the composer, sent with the note as one multipart post, shown in
# the thread, and never lost to a refresh.
class Admin::NoteFilesSystemTest < ApplicationSystemTestCase
  include NoteFilesHelper

  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
    sign_in_via_form(users(:one))
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    assert_eventually(message: "the thread never took the focus") { page.evaluate_script("document.activeElement === document.querySelector('#note-thread-#{@thread.id}')") }
  end

  def reply = "#note-thread-#{@thread.id}-reply"

  def reply_field = find("#{reply} textarea[name=body]")

  # `set` on the field itself: `attach_file` called on an element looks for a
  # file field INSIDE it. The field is out of sight; the paperclip opens it.
  def choose(*paths, within: reply) = find("#{within} input[type=file]", visible: :all).set(paths.map(&:to_s))

  def chosen(within: reply) = all("#{within} [data-admin--note-composer-target=chosen] [data-note-chosen]").map { |row| row.text.squish }

  # A file of its own name with `bytes` of text, for the test to choose.
  def file_of(name, bytes)
    path = Rails.root.join("tmp", "note-files-test", "#{Process.pid}-#{name}")
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, "a" * bytes)
    (@made ||= []) << path
    path
  end

  teardown { Array(@made).each { |path| FileUtils.rm_f(path) } }

  def pdf_path = file_of("report.pdf", 0).tap { |path| File.binwrite(path, PDF) }

  def reduce_motion(on) = page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: on ? "reduce" : "" } ])

  test "an image and a PDF are attached to a reply: both are shown, the composer is empty again, and the picture opens in a new tab through the notes action" do
    open_thread
    assert_selector "#{reply} button[data-note-attach][title='Attach up to 5 files, 10 MB each']"
    choose(file_fixture("tiny.png"), pdf_path)
    assert_equal [ "tiny.png PNG · 1 KB", "#{Process.pid}-report.pdf PDF · 1 KB" ], chosen

    reply_field.send_keys("Two files", [ :control, :enter ])

    note = "#note-thread-#{@thread.id}-messages [data-note-message]:last-child"
    assert_selector "#{note} [data-note-files] a[data-note-image][target=_blank] img[alt='tiny.png']"
    assert_selector "#{note} [data-note-files] a[data-note-file]", text: /report\.pdf\s*PDF · \d+ Bytes/
    # The reply's part is the answer's: no text, no chosen file, nothing in the file field.
    assert_equal "", reply_field.value
    assert_empty chosen
    assert_equal 0, page.evaluate_script("document.querySelector('#{reply} input[type=file]').files.length")
    message = @thread.messages.reload.last
    assert_equal [ "tiny.png", "#{Process.pid}-report.pdf" ], message.files.map { |file| file.filename.to_s }
    assert_equal [ "image/png", "application/pdf" ], message.files.map(&:content_type)

    # The picture is served by the notes action, as the bytes it is.
    image = find("#{note} a[data-note-image]")
    assert_match %r{\A.*/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}/messages/#{message.id}/files/\d+\z}, image[:href]
    assert_eventually(message: "the picture never loaded") { page.evaluate_script("document.querySelector(#{"#{note} a[data-note-image] img".to_json}).naturalWidth") > 0 }
    assert_no_selector "#notes-drawer [src*='active_storage'], #notes-drawer [href*='active_storage']", visible: :all
    tab = window_opened_by { image.click }
    within_window(tab) { assert_match %r{/files/\d+\z}, current_url }
    tab.close
  end

  test "a sixth file and a file over ten megabytes are refused in place, in a line and not a toast, and nothing is sent" do
    open_thread
    choose(*Array.new(4) { |index| file_of("f#{index}.txt", 10) })
    assert_equal 4, chosen.size

    # Two more: one fits, the sixth does not.
    choose(file_of("fifth.txt", 2_000_000), file_of("sixth.txt", 10))

    assert_equal 5, chosen.size
    assert_includes chosen, "#{Process.pid}-fifth.txt TXT · 1.9 MB"
    assert_selector "#{reply} [data-admin--note-composer-target=fileError][class~='text-danger-ink'][class~='text-[12px]']", text: "A note can carry at most 5 files."
    assert_no_selector "#toasts .admin-toast"

    find("#{reply} [data-note-chosen] button[aria-label='Remove #{Process.pid}-fifth.txt']").click
    assert_equal 4, chosen.size
    assert_no_selector "#{reply} [data-admin--note-composer-target=fileError]"

    choose(file_of("big.bin", 10.megabytes + 1))
    assert_equal 4, chosen.size
    assert_selector "#{reply} [data-admin--note-composer-target=fileError]", text: "#{Process.pid}-big.bin is over 10 MB."
    assert_equal 4, page.evaluate_script("document.querySelector('#{reply} input[type=file]').files.length")
    assert_equal 1, Notes::Message.count
  end

  test "a refused file keeps the text, names the file and the reason in the composer, and says to attach the files again" do
    open_thread
    choose(file_fixture("tiny.png"), file_fixture("tiny.svg"))
    reply_field.send_keys("Keep these words", [ :control, :enter ])

    assert_selector "#{reply} [role=alert][class~='text-danger-ink']", text: /tiny\.svg: this type of file can't be attached\.\s*Attach the files again: a browser does not keep them\./
    assert_no_selector "#toasts .admin-toast"
    assert_equal "Keep these words", reply_field.value
    assert_empty chosen
    assert_equal [ 1, 0 ], [ Notes::Message.count, ActiveStorage::Blob.count ]

    # Attached again, without the file that was refused, it goes through once.
    choose(file_fixture("tiny.png"))
    within(reply) { press "Reply" }
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]:last-child [data-note-files] img[alt='tiny.png']"
    assert_writes_settled
    assert_equal [ 2, 1 ], [ Notes::Message.count, ActiveStorage::Blob.count ]
  end

  # The one-send guard, for an upload that takes its time: the press marks
  # the note as out, and it stays out until the answer is in.
  test "a note whose upload is slow is sent once, however often it is sent again meanwhile" do
    open_thread
    choose(file_fixture("tiny.png"))
    reply_field.send_keys("Slowly")
    page.execute_script(<<~JS)
      window.__posts = 0
      const original = window.fetch
      window.fetch = async (...args) => {
        const method = String(args[1]?.method || args[0].method || "GET").toUpperCase()
        if (method !== "POST") return original(...args)
        window.__posts += 1
        await new Promise((release) => { window.__release = release })
        return original(...args)
      }
    JS

    reply_field.send_keys([ :control, :enter ])
    await_js("window.__posts === 1")
    assert_selector "#{reply} button[type=submit][data-admin--note-composer-target=submit][disabled]"
    # The two ways a person sends: the key again, and the button, which is
    # disabled for as long (a press on it does nothing).
    reply_field.send_keys([ :control, :enter ], [ :control, :enter ])
    page.execute_script("document.querySelector('#{reply} button[data-admin--note-composer-target=submit]').click()")
    await_frames
    assert_equal 1, page.evaluate_script("window.__posts")
    assert_equal 1, Notes::Message.count

    page.execute_script("window.__release()")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]:last-child", text: "Slowly"
    assert_writes_settled
    assert_equal [ 2, 1 ], [ Notes::Message.count, ActiveStorage::Blob.count ]
  end

  test "a draft holds the text only: chosen files are gone when the composer is drawn again" do
    open_thread
    choose(file_fixture("tiny.png"))
    reply_field.send_keys("Half a thought")
    assert_eventually { page.evaluate_script("Object.keys(window.sessionStorage).some((name) => name.startsWith('cs-note-draft:'))") }
    assert_no_match(/tiny/, page.evaluate_script("JSON.stringify(Object.entries(window.sessionStorage))"))

    open_thread

    assert_equal "Half a thought", reply_field.value
    assert_empty chosen
  end

  # Notes spec §6.3: what is typed is never replaced by a refresh, and chosen
  # files are typed work that no script could put back.
  test "a reply that arrives live leaves chosen files where they are, with or without text beside them" do
    open_thread
    choose(file_fixture("tiny.png"), file_fixture("small.gif"))
    page.execute_script("window.__files = document.querySelector('#{reply} input[type=file]')")

    as(users(:two)) { assert Notes::Reply.call(@thread, body: "One more thing").ok? }

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "One more thing", wait: LIVE
    assert_equal [ "tiny.png PNG · 1 KB", "small.gif GIF · 1 KB" ], chosen
    assert page.evaluate_script("window.__files.isConnected && window.__files.files.length === 2"), "the file field was drawn again"

    reply_field.send_keys("With both", [ :control, :enter ])
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]:last-child [data-note-files] [data-note-gif]"
    assert_equal %w[tiny.png small.gif], @thread.messages.reload.last.files.map { |file| file.filename.to_s }
  end

  test "a thread deleted under chosen files keeps them, and says so" do
    open_thread
    choose(file_fixture("tiny.png"))
    page.execute_script("window.__files = document.querySelector('#{reply} input[type=file]')")

    as(users(:two)) { assert Notes::DeleteMessage.call(@thread.first_message).ok? }

    assert_selector "#{reply} [data-note-gone]", text: "This thread was deleted", wait: LIVE
    assert_equal [ "tiny.png PNG · 1 KB" ], chosen
    assert page.evaluate_script("window.__files.isConnected && window.__files.files.length === 1")
  end

  test "a new note's chosen files stay while the list around its field is refreshed" do
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    within("#notes-drawer") { press "New note" }
    assert_selector "#notes-new textarea[name=body]"
    choose(file_fixture("tiny.png"), within: "#notes-new")

    as(users(:two)) { assert Notes::Start.call(@page, body: "Started elsewhere").ok? }

    assert_selector "#notes-list a[id^='note-row-']", text: "Started elsewhere", wait: LIVE
    assert_equal [ "tiny.png PNG · 1 KB" ], chosen(within: "#notes-new")
    assert_equal 1, page.evaluate_script("document.querySelector('#notes-new input[type=file]').files.length")
  end

  # A picture's address is never cached, so a refresh that drew the files
  # again would fetch every picture again: the very elements are kept.
  test "a live refresh keeps a message's pictures as the elements they were" do
    as(users(:two)) { assert Notes::Reply.call(@thread, body: "A picture", files: [ fixture_upload("tiny.png") ]).ok? }
    open_thread
    assert_eventually(message: "the picture never loaded") { page.evaluate_script("document.querySelector('[data-note-files] img').naturalWidth") > 0 }
    page.execute_script("window.__picture = document.querySelector('[data-note-files] img')")

    as(users(:two)) { assert Notes::Reply.call(@thread, body: "One more thing").ok? }

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "One more thing", wait: LIVE
    assert page.evaluate_script("window.__picture.isConnected && window.__picture === document.querySelector('[data-note-files] img')"), "the picture was drawn again"
  end

  test "a GIF plays by itself; with reduced motion it is a still with Play, which turns into Pause" do
    as(users(:two)) { assert Notes::Reply.call(@thread, body: "A loop", files: [ fixture_upload("small.gif", name: "loop.gif") ]).ok? }
    open_thread
    tile = "#note-thread-#{@thread.id}-messages [data-note-gif]"
    visible = ->(selector) { page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector(#{"#{tile} #{selector}".to_json})); return style.display !== 'none' && style.opacity !== '0' })()") }

    # Without reduced motion: the picture, no still and no control; its label.
    assert_selector tile, text: "GIF · loop.gif"
    assert_eventually(message: "the GIF never loaded") { page.evaluate_script("document.querySelector(#{"#{tile} img".to_json}).naturalWidth") > 0 }
    assert_equal [ true, false, false ], [ visible.call("img"), visible.call("canvas"), visible.call("button") ]

    reduce_motion(true)
    open_thread
    assert_selector "#{tile} button", text: "Play"
    # The first frame is painted on the canvas over the picture, which is not shown.
    assert_eventually(message: "the still was never painted") { page.evaluate_script("document.querySelector(#{"#{tile} canvas".to_json}).width") == page.evaluate_script("document.querySelector(#{"#{tile} img".to_json}).naturalWidth") }
    assert_equal [ false, true ], [ visible.call("img"), visible.call("canvas") ]

    find("#{tile} button").click
    assert_selector "#{tile} button", text: "Pause"
    assert_equal [ true, false ], [ visible.call("img"), visible.call("canvas") ]

    find("#{tile} button").click
    assert_selector "#{tile} button", text: "Play"
    assert_equal [ false, true ], [ visible.call("img"), visible.call("canvas") ]
  ensure
    reduce_motion(false)
  end

  test "a message's files stay under its edit form, which has no file field" do
    as(users(:one)) { assert Notes::Reply.call(@thread, body: "Mine", files: [ fixture_upload("tiny.png") ]).ok? }
    open_thread
    mine = "#note-thread-#{@thread.id}-messages [data-note-message]:last-child"

    find("#{mine} button[aria-label='Note actions']").click
    find("#{mine} a[data-note-edit]").click

    assert_selector "#{mine} form[data-note-composer] textarea[name=body]"
    assert_no_selector "#{mine} form[data-note-composer] input[type=file]", visible: :all
    assert_no_selector "#{mine} form[data-note-composer] button[data-note-attach]"
    assert_selector "#{mine} > [data-note-files] img[alt='tiny.png']"
  end
end
