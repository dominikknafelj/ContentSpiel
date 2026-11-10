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

  # Every control under `root` as [description, height]: the fields and
  # selects, the Clear link, and each segmented group's
  # frame (its labels are the frame less its two border pixels). A filter
  # panel's fieldset is no segmented group: its selects are measured as
  # selects.
  def heights(root: BAR)
    page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector(#{root.to_json})
        const out = []
        const add = (el, name) => out.push([name, Math.round(el.getBoundingClientRect().height * 100) / 100])
        bar.querySelectorAll("input:not(.sr-only):not([type=hidden]), select").forEach((el) => add(el, el.tagName.toLowerCase() + "#" + el.id))
        bar.querySelectorAll("a[data-turbo-frame]:not([aria-label])").forEach((el) => add(el, "link " + el.textContent.trim()))
        bar.querySelectorAll("fieldset:not(.admin-filter-panel) > div").forEach((el) => add(el, "segments"))
        return out
      })()
    JS
  end

  def assert_one_height(expected_names, root: BAR)
    assert_selector root
    measured = heights(root:)
    names = measured.map(&:first)
    expected_names.each { |name| assert(names.any? { |n| n.start_with?(name) }, "#{name} is in the bar: #{names}") }
    measured.each { |name, height| assert_in_delta HEIGHT, height, 0.5, "#{name} is #{height}px, the bar is #{HEIGHT}px (#{measured})" }
    assert_selector(root == BAR ? "#{BAR}.admin-filter-bar" : "#{root} .admin-filter-bar")
  end

  # The posts list's form is `display: contents` and holds the bar and the
  # filter panel, so it is measured whole: the panel's selects are the
  # bar's height wherever the panel stands.
  test "the posts list's bar and its filter panel: search, segments, Clear and the three selects are one height" do
    [ 1600, 1100 ].each do |width|
      at_window(width) do
        visit_screen admin_posts_path(scope: "drafts")
        assert_one_height(%w[input#q segments select#type select#tag select#translation link\ Clear], root: "form#posts-filters")
      end
    end
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

  # The subject chip is the chip input's pill, not a control of the row: it
  # is as tall as a tag chip in the post editor, and its × is the pill's own
  # 20px button.
  test "the audit log's bar: its selects and Clear are one height, and the subject chip is the chip input's pill" do
    post = create_post(title: "Chip", tags: [ "ruby" ])
    visit_editor post
    pill = page.evaluate_script("document.querySelector('.admin-chip-field li.admin-chip').getBoundingClientRect().height")

    visit_screen admin_audit_events_path(subject_type: "Post", subject_id: post.id, range: "7")
    assert_one_height(%w[select#user_id select#event_action select#channel select#range link\ Clear])
    chip = page.evaluate_script("document.querySelector('#{BAR} [data-subject-chip]').getBoundingClientRect().height")
    assert_in_delta pill, chip, 0.5, "the subject chip is #{chip}px, a chip input's pill is #{pill}px"
    assert_operator chip, :<, HEIGHT - 4, "the subject chip is not stretched to the bar's height"
    assert_equal 20, page.evaluate_script("Math.round(document.querySelector('#{BAR} [data-subject-chip] a').getBoundingClientRect().height)")

    visit_screen admin_audit_events_path(range: "custom")
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
    page.current_window.resize_to(380, 900)
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
    page.current_window.resize_to(1400, 1400)
  end
end
