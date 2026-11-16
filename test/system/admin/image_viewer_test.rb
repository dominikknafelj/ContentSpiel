require "application_system_test_case"
require "support/note_files_helper"

# The image viewer (`Admin::Ui::ImageViewerComponent`, `admin--ui--image-viewer`;
# the image viewer spec §4): a plain click on a note's picture opens it over
# CS Studio, its arrows and ← → step through that message's pictures only, and
# it closes back to the picture that opened it. Its first caller is the notes,
# so every test opens a thread whose reply holds two pictures and a PDF, and
# a second message holds one picture more.
class Admin::ImageViewerSystemTest < ApplicationSystemTestCase
  include NoteFilesHelper

  VIEWER = "dialog#image-viewer".freeze
  TARGET = "data-admin--ui--image-viewer-target".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
    as(users(:two)) do
      assert Notes::Reply.call(@thread, body: "Two pictures and a report",
        files: [ fixture_upload("tiny.png"), fixture_upload("wide.png"), note_upload(PDF, "report.pdf") ]).ok?
      assert Notes::Reply.call(@thread, body: "One more", files: [ fixture_upload("medium.png") ]).ok?
    end
    @pictures = @thread.messages.order(:created_at).second.files_attachments.order(:id).to_a
    sign_in_via_form(users(:one))
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_thread
    visit_screen "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    await_notes_still
  end

  def thumbnail(name) = "#notes-drawer a[data-image-viewer-item][data-name='#{name}']"

  def part(name) = "#{VIEWER} [#{TARGET}='#{name}']"

  def position = find(part("position")).text

  def title = find("#{VIEWER} h2#image-viewer-title").text

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  # The thumbnail's picture is already in the browser's memory, and a step
  # to its address draws it from there without asking the server: a query
  # added to the link's address (which the notes action ignores) makes the
  # viewer's request one the server answers, as for a picture not seen yet.
  def unseen(name) = page.execute_script("const link = document.querySelector(#{thumbnail(name).to_json}); link.href = `${link.href}?unseen`")

  def open_viewer(name)
    find(thumbnail(name)).click
    assert_selector "#{VIEWER}[open]"
    assert_equal name, title
  end

  def reduce_motion(on) = page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: on ? "reduce" : "" } ])

  # Keeps the picture's request in flight: the browser's own request for
  # `pattern` is paused (Chrome's Fetch domain) until the block releases it
  # by `continue`, or the interception ends with the block.
  def holding(pattern)
    browser = page.driver.browser.page
    held = []
    listener = browser.on(:request) { |request| held << request }
    browser.network.intercept(pattern: pattern)
    yield held
  ensure
    browser.command("Fetch.disable")
    browser.off(:request, listener) if listener
  end

  test "a plain click on a note's picture opens the viewer with its name, facts and position" do
    open_thread
    link = find(thumbnail("tiny.png"))
    link.find("img").click

    assert_selector "#{VIEWER}[open]"
    assert_equal "tiny.png", title
    assert_match(/\APNG · \d+ Bytes\z/, find(part("facts")).text)
    assert_equal "1 of 2", position
    assert_equal link[:href], find(part("original"))[:href]
    assert_equal link[:href], find(part("download"))[:href]
    assert_equal "tiny.png", find(part("download"))[:download]
    assert_equal "tiny.png", find(part("picture"))[:alt]
    assert_eventually(message: "the picture never loaded") { page.evaluate_script("document.querySelector(#{part('picture').to_json}).naturalWidth") > 0 }
    assert_equal 1, windows.size, "the click opened a window as well"
  end

  test "a modified click on a note's picture opens a tab and not the viewer" do
    open_thread
    apple = page.evaluate_script("/mac|iphone|ipad|ipod/i.test(navigator.userAgentData?.platform || navigator.platform || '')")
    tab = window_opened_by { find(thumbnail("tiny.png")).click(apple ? :meta : :control) }
    assert_no_selector "#{VIEWER}[open]"
    tab.close
  end

  test "the arrows step through one message's pictures only, disabled at the ends, and say the name and position" do
    open_thread
    open_viewer("tiny.png")
    assert_equal "1 of 2", position
    assert_selector "#{part('previous')}[disabled]"
    assert_no_selector "#{part('next')}[disabled]"
    assert_equal "", find(part("announcer"), visible: :all).text(:all), "the opening is announced by the dialog's name, not the live region"

    find(part("next")).click
    assert_equal "2 of 2", position
    assert_equal "wide.png", title
    assert_selector "#{part('next')}[disabled]"
    assert_no_selector "#{part('previous')}[disabled]"
    assert_equal "wide.png, 2 of 2", find(part("announcer"), visible: :all).text(:all)
    assert_no_text "of 3"

    find(part("previous")).click
    assert_equal "1 of 2", position
    assert_equal "tiny.png, 1 of 2", find(part("announcer"), visible: :all).text(:all)
  end

  # The component's keyboard (its contract's `keyboard:`).
  test "the keyboard reaches a note's picture with Tab, Enter opens the viewer on Next, the arrows step, and Escape gives the focus back to the picture" do
    open_thread
    stop_on(thumbnail("tiny.png"))
    page.send_keys(:enter)

    assert_selector "#{VIEWER}[open]"
    assert_equal 1, windows.size
    assert focused?(part("next")), "the opening did not give the focus to Next"

    page.send_keys(:right)
    assert_equal "2 of 2", position
    assert focused?(part("previous")), "Next became disabled and the focus did not move to Previous"

    page.send_keys(:left)
    assert_equal "1 of 2", position

    page.send_keys(:escape)
    assert_no_selector "#{VIEWER}[open]"
    assert_eventually(message: "the focus did not go back to the picture") { focused?(thumbnail("tiny.png")) }
    # One Escape, one layer: the notes under the viewer stay open on the thread.
    assert_selector "#notes-drawer [data-notes-view=thread]"
  end

  test "an arrow with a modifier does not step" do
    open_thread
    open_viewer("tiny.png")
    page.send_keys([ :alt, :right ])
    page.send_keys([ :shift, :right ])
    await_frames
    assert_equal "1 of 2", position
  end

  test "a picture that can't be loaded says so and keeps Open original and Download" do
    open_thread
    unseen("wide.png")
    open_viewer("tiny.png")
    # The file is gone under the open page: the notes action answers 404.
    ActiveStorage::Attachment.where(id: @pictures.second.id).delete_all

    find(part("next")).click
    assert_selector part("notice"), text: "This image couldn't be shown here. Open the original, or download it."
    assert_no_selector part("picture")
    assert_equal "wide.png", title
    assert_selector "#{part('original')}[href$='/files/#{@pictures.second.id}?unseen']"
    assert_selector "#{part('download')}[href$='/files/#{@pictures.second.id}?unseen'][download='wide.png']"

    # A step away takes the notice back.
    find(part("previous")).click
    assert_no_selector part("notice")
    assert_selector part("picture")
  end

  test "with reduced motion a GIF in the viewer is a still with Play, and each opening starts it still" do
    as(users(:two)) { assert Notes::Reply.call(@thread, body: "A loop", files: [ fixture_upload("tiny.png", name: "first.png"), fixture_upload("small.gif", name: "loop.gif") ]).ok? }
    reduce_motion(true)
    open_thread
    stage_button = "#{part('frame')} button"

    # From a PNG to the GIF: the still is painted when the step says GIF.
    open_viewer("first.png")
    assert_no_selector stage_button
    find(part("next")).click
    assert_equal "loop.gif", title
    assert_selector stage_button, text: "Play"
    assert_eventually(message: "the GIF's still was never painted") { page.evaluate_script("document.querySelector(#{"#{part('frame')} canvas".to_json}).width") > 0 }

    find(stage_button).click
    assert_selector stage_button, text: "Pause"

    page.send_keys(:escape)
    assert_no_selector "#{VIEWER}[open]"

    # Opened again on the GIF itself (by its link: its tile's Play stands over its middle).
    page.execute_script("document.querySelector(#{thumbnail('loop.gif').to_json}).focus()")
    page.send_keys(:enter)
    assert_selector "#{VIEWER}[open]"
    assert_equal "loop.gif", title
    assert_selector stage_button, text: "Play"
  ensure
    reduce_motion(false)
  end

  test "a slow picture shows Loading after 400 ms, a cached one never does" do
    open_thread
    unseen("wide.png")
    open_viewer("tiny.png")
    assert_eventually(message: "the picture never loaded") { page.evaluate_script("document.querySelector(#{part('picture').to_json}).naturalWidth") > 0 }
    loading = part("loading")

    holding("*/files/#{@pictures.second.id}?unseen") do |held|
      # What the step left right after it ran: no Loading yet.
      page.execute_script("document.addEventListener('click', () => { window.__loadingAtStep = document.querySelector(#{loading.to_json}).hidden }, { once: true })")
      find(part("next")).click
      assert page.evaluate_script("window.__loadingAtStep"), "Loading showed at once"
      assert_no_selector part("picture"), wait: 0
      assert_selector loading, text: "Loading…"
      assert_equal 1, held.size

      held.each(&:continue)
      assert_no_selector loading
      assert_selector part("picture")
    end

    # Back to the picture already loaded: Loading never shows.
    page.execute_script(<<~JS)
      window.__loadingShown = false
      const loading = document.querySelector(#{loading.to_json})
      new MutationObserver(() => { if (!loading.hidden) window.__loadingShown = true }).observe(loading, { attributes: true })
    JS
    find(part("previous")).click
    assert_equal "1 of 2", position
    sleep 0.6 # sleep: outlasts the viewer's 400 ms Loading timer, to show it never fired
    assert_not page.evaluate_script("window.__loadingShown"), "a loaded picture showed Loading"
    assert_selector part("picture")
  end

  test "a picture larger than the stage is fitted inside it, and a long name truncates while the dialog keeps it whole" do
    name = "a-picture-with-a-very-long-name-that-runs-on-and-on-past-the-head-of-the-viewer-#{"and-on-" * 20}.png"
    as(users(:two)) { assert Notes::Reply.call(@thread, body: "Long", files: [ fixture_upload("tiny.png", name: name) ]).ok? }
    open_thread
    # Four messages: the thread folds the middle ones, the pictures' among them.
    find("#notes-drawer summary", text: "Show 1 more").click

    open_viewer("wide.png")
    assert_eventually(message: "the picture never loaded") { page.evaluate_script("document.querySelector(#{part('picture').to_json}).naturalWidth") > 0 }
    picture, stage = [ part("picture"), part("stage") ].map { |selector| page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ r.left, r.top, r.right, r.bottom ] })()") }
    assert picture[0] >= stage[0] - 0.5 && picture[1] >= stage[1] - 0.5 && picture[2] <= stage[2] + 0.5 && picture[3] <= stage[3] + 0.5, "the picture reaches out of the stage: #{picture} in #{stage}"
    page.send_keys(:escape)
    assert_no_selector "#{VIEWER}[open]"

    # One picture: no arrows.
    open_viewer(name)
    assert_equal "1 of 1", position
    assert_no_selector part("previous")
    assert_no_selector part("next")
    head = "#{VIEWER} h2#image-viewer-title"
    assert page.evaluate_script("(() => { const h2 = document.querySelector(#{head.to_json}); return h2.scrollWidth > h2.clientWidth && getComputedStyle(h2).textOverflow === 'ellipsis' })()"), "the long name does not truncate"
    assert_equal name, page.evaluate_script("document.querySelector(#{head.to_json}).textContent.trim()")
  end

  test "a phone draws the viewer over the whole screen with the arrows in the foot" do
    at_window(390, height: 760) do
      open_thread
      open_viewer("tiny.png")
      rect = page.evaluate_script("(() => { const r = document.querySelector('#{VIEWER}').getBoundingClientRect(); return [ r.left, r.top, r.width, r.height, window.innerWidth, window.innerHeight ] })()")
      assert_equal [ 0, 0, rect[4], rect[5] ], rect.first(4).map(&:round)
      assert_no_selector part("previous")
      assert_no_selector part("next")
      assert_selector "#{part('phonePrevious')}[disabled]"
      assert_selector part("phoneNext")
      assert focused?(part("phoneNext")), "the opening did not give the focus to the foot's Next"

      find(part("phoneNext")).click
      assert_equal "2 of 2", position
      assert focused?(part("phonePrevious")), "the foot's Next became disabled and the focus did not move to its Previous"
    end
  end

  test "the viewer is closed and empty in Turbo's snapshot: Back shows no open viewer" do
    open_thread
    open_viewer("tiny.png")
    # A visit while the viewer is open: the modal stands over every link, so
    # the visit is started by script, as a link's would be.
    page.execute_script("Turbo.visit('/cs-studio/media')")
    assert_current_path "/cs-studio/media"
    await_admin_controllers

    page.go_back
    assert_current_path(/\/cs-studio\/pages\/#{@page.id}/)
    assert_no_selector "#{VIEWER}[open]", visible: :all
    assert_no_selector "#image-viewer img[src]", visible: :all
    assert_no_selector "#image-viewer a[href]", visible: :all
    assert_equal "", find("#image-viewer h2", visible: :all).text(:all).strip
  end
end
