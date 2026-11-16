require "application_system_test_case"

# The Gallery block's carousel on the public site, in a browser: the
# `gallery-carousel` script (gallery block spec §7.3 to §7.5). Each test
# draws a published page holding one carousel of library images and reads
# the carousel's state through one script call (`state`), so what a test
# compares is what a visitor's page holds at one moment.
#
# A move by a button or a key is marked at once (the position, the picker,
# the buttons, the state and the status), and the track then scrolls to the
# slide; `await_shown` waits for the slide to stand in the track, which is
# what a person sees.
class GalleryBlockSystemTest < ApplicationSystemTestCase
  CAROUSEL = "section.content-block--gallery--carousel".freeze
  TRACK = "#{CAROUSEL} [data-gallery-carousel-target=track]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Walks")
  end

  # The emulated media and a direction set by a test are the shared
  # browser's: both are taken back.
  teardown do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
    page.execute_script("document.documentElement.removeAttribute('dir')")
  end

  def add_carousel(count)
    assets = Array.new(count) { create_media_asset }
    @page.content_blocks.create!(block_type: :gallery, position: 0, settings: { "layout" => "carousel", "images" => assets.map(&:id) })
  end

  def open_page(path = PublicSite::Urls.new.path_for(@page, "en"))
    publish_changes(@page)
    visit path
    await_connected
  end

  CONNECTED = "(() => { const carousel = document.querySelector('#{CAROUSEL}'); return Boolean(window.Stimulus && carousel && window.Stimulus.getControllerForElementAndIdentifier(carousel, 'gallery-carousel')) })()".freeze

  def await_connected = await_js(CONNECTED, message: "the carousel's script never connected")

  def reduce_motion(on) = page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: on ? "reduce" : "no-preference" } ])

  # What the carousel says and shows at one moment.
  STATE = <<~JS.freeze
    (() => {
      const carousel = document.querySelector("#{CAROUSEL}")
      const part = (name) => carousel.querySelector(`[data-gallery-carousel-target=${name}]`)
      const picks = Array.from(carousel.querySelectorAll("[data-gallery-carousel-target=pick]"))
      return {
        state: carousel.dataset.galleryCarouselState || null,
        position: part("position").textContent,
        status: part("status").textContent,
        current: picks.map((pick) => pick.getAttribute("aria-current")),
        previous: part("previous").disabled,
        next: part("next").disabled,
        hidden: [ part("controls").hidden, part("position").parentElement.hidden, picks[0] ? picks[0].parentElement.hidden : null, part("status").hidden ]
      }
    })()
  JS

  def state = page.evaluate_script(STATE).transform_keys(&:to_sym)

  # The slide (1-based) whose start stands at the track's start, within a
  # pixel, read from the rectangles: the one a person sees.
  SHOWN = <<~JS.freeze
    (() => {
      const track = document.querySelector("#{TRACK}")
      const box = track.getBoundingClientRect()
      const rtl = getComputedStyle(track).direction === "rtl"
      const slides = Array.from(track.querySelectorAll("[data-gallery-carousel-target=slide]"))
      return slides.findIndex((slide) => { const rect = slide.getBoundingClientRect(); return Math.abs(rtl ? rect.right - box.right : rect.left - box.left) < 1 }) + 1
    })()
  JS

  def shown = page.evaluate_script(SHOWN)

  def await_shown(index) = await_js("#{SHOWN.strip} === #{index}", message: "slide #{index} never stood in the track")

  def press_button(name) = find("#{CAROUSEL} button[aria-label='#{name}']").click

  def focused = page.evaluate_script("document.activeElement.getAttribute('aria-label')")

  def at(index, of:, status:)
    { position: "#{index} of #{of}", status: status, state: index == 1 ? "first" : (index == of ? "last" : "middle") }
  end

  def assert_at(index, of:, status:)
    now = state
    assert_equal at(index, of: of, status: status), now.slice(:position, :status, :state)
    assert_equal Array.new(of) { |each| each + 1 == index ? "true" : nil }, now[:current] if of <= BlockTypes::Gallery::PICKER_MAX
    assert_equal [ index == 1, index == of ], [ now[:previous], now[:next] ], "Previous and Next disabled at the ends"
  end

  test "next, previous and a pick move one image, disable at the ends and say where we are" do
    add_carousel(3)
    open_page

    assert_equal [ false, false, false, false ], state[:hidden], "the controls, the foot, the picker and the status are shown"
    assert_at 1, of: 3, status: ""

    press_button "Next image"
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2
    press_button "Next image"
    assert_at 3, of: 3, status: "Image 3 of 3"
    await_shown 3

    # At the end Next is disabled and nothing wraps.
    page.execute_script("document.querySelector('#{CAROUSEL} [data-gallery-carousel-target=next]').click()")
    assert_at 3, of: 3, status: "Image 3 of 3"

    press_button "Previous image"
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2

    press_button "Show image 1"
    assert_at 1, of: 3, status: "Image 1 of 3"
    await_shown 1
    press_button "Show image 3"
    assert_at 3, of: 3, status: "Image 3 of 3"
    await_shown 3
  end

  test "a disabled button hands the focus to the other one" do
    add_carousel(2)
    open_page

    press_button "Next image"
    assert_at 2, of: 2, status: "Image 2 of 2"
    assert_equal "Previous image", focused, "Next is disabled at the last image, and the focus is on Previous, never on the page"

    press_button "Previous image"
    assert_at 1, of: 2, status: "Image 1 of 2"
    assert_equal "Next image", focused
  end

  test "the arrow keys, Home and End move on the track and on the controls, never with a modifier" do
    add_carousel(4)
    open_page
    track = find(TRACK)
    page.execute_script("document.querySelector('#{TRACK}').focus()")

    track.send_keys(:right)
    assert_at 2, of: 4, status: "Image 2 of 4"
    await_shown 2
    track.send_keys(:end)
    assert_at 4, of: 4, status: "Image 4 of 4"
    await_shown 4
    track.send_keys(:left)
    assert_at 3, of: 4, status: "Image 3 of 4"
    await_shown 3
    track.send_keys(:home)
    assert_at 1, of: 4, status: "Image 1 of 4"
    await_shown 1

    # Nothing wraps: at the first image Left and Home, at the last Right and
    # End, change nothing and say nothing new.
    [ :left, :home ].each do |key|
      track.send_keys(key)
      await_frames
      assert_at 1, of: 4, status: "Image 1 of 4"
      assert_equal 1, shown
    end
    track.send_keys(:end)
    assert_at 4, of: 4, status: "Image 4 of 4"
    await_shown 4
    [ :right, :end ].each do |key|
      track.send_keys(key)
      await_frames
      assert_at 4, of: 4, status: "Image 4 of 4"
      assert_equal 4, shown
    end
    track.send_keys(:home)
    assert_at 1, of: 4, status: "Image 1 of 4"
    await_shown 1

    # With a modifier the key is the browser's or the system's: the script
    # neither moves nor speaks, and leaves the key's default alone.
    [ :alt, :control, :meta ].each do |modifier|
      prevented = page.evaluate_script(<<~JS)
        (() => {
          const event = new KeyboardEvent("keydown", { key: "ArrowRight", #{modifier == :control ? "ctrlKey" : "#{modifier}Key"}: true, bubbles: true, cancelable: true })
          document.querySelector("#{TRACK}").dispatchEvent(event)
          return event.defaultPrevented
        })()
      JS
      assert_not prevented, "#{modifier}+Right is left to the browser"
      assert_at 1, of: 4, status: "Image 1 of 4"
    end

    # On the controls: a key on a button moves the carousel too, and End
    # disables the focused Next, so the focus goes to Previous.
    find("#{CAROUSEL} button[aria-label='Next image']").send_keys(:end)
    assert_at 4, of: 4, status: "Image 4 of 4"
    assert_equal "Previous image", focused
    find("#{CAROUSEL} button[aria-label='Previous image']").send_keys(:left)
    assert_at 3, of: 4, status: "Image 3 of 4"
  end

  test "a swipe or a scroll moves the position and the picker but says nothing" do
    add_carousel(3)
    open_page

    press_button "Next image"
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2

    # The browser's own scroll, as a swipe or a trackpad makes it: one
    # slide's width towards the end.
    page.execute_script("const track = document.querySelector('#{TRACK}'); track.scrollBy({ left: track.clientWidth, behavior: 'instant' })")
    await_shown 3
    assert_eventually(message: "the position never followed the scroll") { state[:position] == "3 of 3" }
    assert_at 3, of: 3, status: ""

    page.execute_script("document.querySelector('#{TRACK}').scrollTo({ left: 0, behavior: 'instant' })")
    await_shown 1
    assert_eventually(message: "the position never followed the scroll") { state[:position] == "1 of 3" }
    assert_at 1, of: 3, status: ""
  end

  # The test browser scrolls at once whatever it is asked (Ferrum starts
  # Chrome with smooth scrolling off), so what is held is what the script
  # asks for: `instant` under reduced motion, `smooth` otherwise, and the
  # track at its slide in the press's own task when reduced.
  test "with reduced motion a move is instant" do
    reduce_motion(true)
    add_carousel(3)
    open_page
    page.execute_script(<<~JS)
      const track = document.querySelector("#{TRACK}")
      const scrollTo = track.scrollTo.bind(track)
      window.__behaviors = []
      track.scrollTo = (options) => { window.__behaviors.push(options.behavior); scrollTo(options) }
    JS

    # In one task: the press, and where the track stands right after it.
    standing = page.evaluate_script(<<~JS)
      (() => {
        document.querySelector("#{CAROUSEL} [data-gallery-carousel-target=next]").click()
        return #{SHOWN.strip}
      })()
    JS
    assert_equal 2, standing, "the track stands at the next slide in the same task as the press"
    assert_equal [ "instant" ], page.evaluate_script("window.__behaviors")

    reduce_motion(false)
    press_button "Next image"
    await_shown 3
    assert_equal [ "instant", "smooth" ], page.evaluate_script("window.__behaviors")
  end

  test "in a right-to-left page the buttons follow reading order and the arrow keys the screen" do
    add_carousel(3)
    open_page
    page.execute_script("document.documentElement.setAttribute('dir', 'rtl')")
    await_shown 1

    # Reading order: Previous at the right, Next at the left, the position at the inline end (the left).
    rects = page.evaluate_script(<<~JS)
      (() => {
        const carousel = document.querySelector("#{CAROUSEL}")
        const x = (name) => carousel.querySelector(`[data-gallery-carousel-target=${name}]`).getBoundingClientRect().left
        return [ x("previous"), x("next"), x("position"), carousel.querySelector("[data-gallery-carousel-target=pick]").parentElement.getBoundingClientRect().left ]
      })()
    JS
    previous, following, position, picks = rects
    assert_operator previous, :>, following, "Previous stands at the right"
    assert_operator position, :<, picks, "the position stands at the left"

    press_button "Next image"
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2
    assert_operator page.evaluate_script("document.querySelector('#{TRACK}').scrollLeft"), :<, 0, "the next slide lies to the left"

    # The arrow keys follow the screen: Left goes to the image on the left, the next one.
    track = find(TRACK)
    page.execute_script("document.querySelector('#{TRACK}').focus()")
    track.send_keys(:left)
    assert_at 3, of: 3, status: "Image 3 of 3"
    await_shown 3
    track.send_keys(:right)
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2
    track.send_keys(:home)
    assert_at 1, of: 3, status: "Image 1 of 3"
    await_shown 1
  end

  # Without the script the carousel is its track: the browser's scroll with
  # snap, and none of what only the script makes work. The script is kept
  # from loading by aborting its module's request (the cache off, so the
  # copy an earlier visit fetched is not used), which the registration
  # reports in the console.
  test "without the script the track scrolls and snaps and no control shows" do
    add_carousel(3)
    publish_changes(@page)
    with_script_blocked("gallery_carousel_controller") do
      visit PublicSite::Urls.new.path_for(@page, "en")
      expect_js_error(/Failed to register controller: gallery-carousel/)
      assert_selector "#{TRACK}[tabindex='0'][aria-label='Images']"
      now = state
      assert_equal [ true, true, true, true ], now[:hidden], "the controls, the foot, the picker and the status stay hidden"
      assert_nil now[:state]
      assert_equal "thin", page.evaluate_script("getComputedStyle(document.querySelector('#{TRACK}')).scrollbarWidth"), "the track's own scrollbar says there is more"

      # A scroll of part of a slide snaps to a whole one.
      page.execute_script("const track = document.querySelector('#{TRACK}'); track.scrollBy({ left: track.clientWidth * 0.7, behavior: 'instant' })")
      await_shown 2
    end
  end

  def with_script_blocked(name)
    network = page.driver.browser.network
    network.cache(disable: true)
    network.blocklist = [ %r{/controllers/#{Regexp.escape(name)}[-.]} ]
    yield
  ensure
    network.blocklist = []
    network.cache(disable: false)
  end

  test "back to a cached page the carousel shows no stale words" do
    add_carousel(3)
    open_page

    press_button "Next image"
    assert_at 2, of: 3, status: "Image 2 of 3"
    await_shown 2

    find("header a", match: :first).click
    # wait: the carousel goes when Turbo has fetched and drawn the page the link leads to.
    assert_no_selector CAROUSEL, wait: 8

    page.go_back
    await_connected
    await_shown 1
    assert_at 1, of: 3, status: ""
    assert_equal [ false, false, false, false ], state[:hidden]
  end

  test "taken off its element, the script puts back what the server drew" do
    add_carousel(3)
    open_page
    press_button "Next image"
    assert_at 2, of: 3, status: "Image 2 of 3"

    page.execute_script("document.querySelector('#{CAROUSEL}').removeAttribute('data-controller')")
    await_js("!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{CAROUSEL}'), 'gallery-carousel')")
    now = state
    assert_equal({ state: nil, position: "1 of 3", status: "", current: [ "true", nil, nil ], previous: false, next: false, hidden: [ true, true, true, true ] }, now)
  end
end
