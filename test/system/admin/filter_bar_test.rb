require "application_system_test_case"

# The filter bar's one height (Design System: "Controls in one row share one
# height. Forms are 42px; a filter bar is 38px, set by the bar, never by a
# control"). Measured, not read from classes: `.cs-select` is unlayered CSS and
# beats a utility, so a `py-*` written beside it is dead, and only a browser
# says what the controls come to. 38px is `--cs-control-compact` (2.375rem) at a
# root font size of 16px.
class Admin::FilterBarSystemTest < ApplicationSystemTestCase
  BAR = "form.admin-filter-bar".freeze
  HEIGHT = 38

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  # Every control of the bar as [description, height]: the fields and selects,
  # the Clear link, the subject chip, and each segmented group's frame (its
  # labels are the frame less its two border pixels).
  def heights
    page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector("#{BAR}")
        const out = []
        const add = (el, name) => out.push([name, Math.round(el.getBoundingClientRect().height * 100) / 100])
        bar.querySelectorAll("input:not(.sr-only):not([type=hidden]), select").forEach((el) => add(el, el.tagName.toLowerCase() + "#" + el.id))
        bar.querySelectorAll("a[data-turbo-frame]:not([aria-label])").forEach((el) => add(el, "link " + el.textContent.trim()))
        bar.querySelectorAll("[data-subject-chip]").forEach((el) => add(el, "chip"))
        bar.querySelectorAll("fieldset > div").forEach((el) => add(el, "segments"))
        return out
      })()
    JS
  end

  def assert_one_height(expected_names)
    assert_selector BAR
    measured = heights
    names = measured.map(&:first)
    expected_names.each { |name| assert(names.any? { |n| n.start_with?(name) }, "#{name} is in the bar: #{names}") }
    measured.each { |name, height| assert_in_delta HEIGHT, height, 0.5, "#{name} is #{height}px, the bar is #{HEIGHT}px (#{measured})" }
    assert_selector "#{BAR}.admin-filter-bar"
  end

  test "the posts list's bar: search, segments, three selects and Clear are one height" do
    visit admin_posts_path(scope: "drafts")
    await_admin_controllers
    assert_one_height(%w[input#q segments select#type select#tag select#translation link\ Clear])
  end

  test "the media library's bar: search, segments and Clear are one height" do
    visit admin_media_path(q: "zz")
    await_admin_controllers
    assert_one_height(%w[input#q segments link\ Clear])
  end

  test "the media picker's bar is the same height" do
    page_record = create_page(title: "Landing")
    assert Pages::Save.call(page_record, attributes: { template: "landing" }).ok?
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers
    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog[open] #{BAR}"
    within("dialog[open]") do
      fill_in "Search images", with: "zz"
      assert_selector "a", text: "Clear"
      assert_one_height(%w[input#media-picker-q segments link\ Clear])
    end
  end

  test "the audit log's bar: its selects, the subject chip and Clear are one height" do
    post = create_post(title: "Chip")
    visit admin_audit_events_path(subject_type: "Post", subject_id: post.id, range: "7")
    await_admin_controllers
    assert_one_height(%w[select#user_id select#event_action chip select#channel select#range link\ Clear])

    visit admin_audit_events_path(range: "custom")
    assert_one_height(%w[select#user_id select#subject_type input#from input#to])
  end

  test "the translations bar: its segments and Clear are one height" do
    with_locales(%w[en de es], default: "en")
    create_page(title: "Untranslated page")
    create_post(title: "Untranslated post")
    visit admin_translations_path(type: "post")
    await_admin_controllers
    assert_one_height(%w[segments link\ Clear])
  end

  test "the translations bar shows no Clear with no filter set" do
    with_locales(%w[en de es], default: "en")
    create_page(title: "Untranslated page")
    create_post(title: "Untranslated post")
    visit admin_translations_path
    await_admin_controllers
    assert_selector BAR
    assert_no_selector "#{BAR} a", text: "Clear"
  end

  # In the form now, and a link: following it submits nothing, so neither the
  # chosen type nor the form's hidden language comes along.
  test "the translations bar's Clear goes to the whole list and does not submit the form" do
    with_locales(%w[en de es], default: "en")
    create_page(title: "Untranslated page")
    create_post(title: "Untranslated post")
    visit admin_translations_path(type: "post", language: "de")
    await_admin_controllers
    within(BAR) { assert_equal "/cs-studio/translations", URI(find("a", text: "Clear")[:href]).path }
    page.execute_script(<<~JS)
      window.__submits = 0
      document.querySelector("#{BAR}").addEventListener("submit", () => { window.__submits += 1 })
    JS

    click_frame_link("Clear")

    assert_no_selector "#{BAR} a", text: "Clear"
    assert_equal "/cs-studio/translations", page.current_url.then { |url| URI(url).request_uri }
    assert find("#translations-type-all", visible: :all).checked?
    assert_equal 0, page.evaluate_script("window.__submits ?? 0")
  end

  test "a wrapped segment row still shows every segment, inside its frame" do
    visit admin_media_path
    await_admin_controllers
    assert_selector BAR
    page.driver.resize(380, 900)
    labels = "#{BAR} fieldset label"
    assert_selector labels, minimum: 4
    result = page.evaluate_script(<<~JS)
      (() => {
        const frame = document.querySelector("#{BAR} fieldset > div").getBoundingClientRect()
        return [...document.querySelectorAll("#{labels}")].map((l) => {
          const r = l.getBoundingClientRect()
          return { text: l.textContent.trim().replace(/\\s+/g, " "), inside: r.top >= frame.top - 0.5 && r.bottom <= frame.bottom + 0.5 && r.left >= frame.left - 0.5 && r.right <= frame.right + 0.5, height: r.height }
        })
      })()
    JS
    assert_operator result.size, :>=, 4
    result.each do |label|
      assert label["inside"], "#{label["text"]} is clipped by its group: #{result}"
      assert_operator label["height"], :>=, HEIGHT - 2 - 0.5, "#{label["text"]} is shorter than its row"
    end
  ensure
    page.driver.resize(1400, 1400)
  end
end
