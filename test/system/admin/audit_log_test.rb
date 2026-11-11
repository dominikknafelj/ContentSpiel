require "application_system_test_case"

# The audit log in a real browser: filters apply on choosing, Custom reveals
# From and To, a row opens its event page, Older/Newer walk the filtered
# list, and a day's band sticks under the top bar while its rows scroll.
class Admin::AuditLogSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @recent = Audit::Event.create!(action: "test.recent", channel: "admin", user_id: users(:one).id, subject_label: "Recent thing",
      occurred_at: 1.hour.ago, last_occurred_at: 1.hour.ago)
    @old = Audit::Event.create!(action: "test.old", channel: "mcp", user_id: users(:one).id, subject_label: "Old thing",
      occurred_at: 40.days.ago, last_occurred_at: 40.days.ago)
    sign_in_via_form(users(:one))
  end

  test "choosing a date preset or a channel applies at once; Custom reveals the two dates" do
    visit_screen admin_audit_events_path
    assert_selector "#audit_event_#{@recent.id}"
    assert_selector "#audit_event_#{@old.id}"

    # Each choice submits the filter form into the content frame, and the
    # answer re-renders the toolbar itself: the next choice is only made once
    # that navigation is over (`click_frame_link` waits for the promoted
    # visit), or it lands on a select that is about to be replaced and is
    # lost with it.
    click_frame_link { select "Last 30 days", from: "Date" }
    assert_no_selector "#audit_event_#{@old.id}", wait: 5
    assert_selector "#audit_event_#{@recent.id}"

    click_frame_link { select "Custom…", from: "Date" }
    assert_selector "input#from", wait: 5
    assert_selector "input#to"

    click_frame_link { select "Any time", from: "Date" }
    assert_selector "#audit_event_#{@old.id}", wait: 5
    click_frame_link { select "MCP", from: "Channel" }
    assert_no_selector "#audit_event_#{@recent.id}", wait: 5
    assert_selector "#audit_event_#{@old.id}"
    assert_no_selector "input#from"
  end

  test "a row opens its event page, and Older goes to the next event in the list" do
    visit_screen admin_audit_events_path

    time_link = find("#audit_event_#{@recent.id} a.text-label")
    assert_no_match(/mono/i, time_link.evaluate_script("getComputedStyle(this).fontFamily"))
    time_link.click
    assert_selector "h1", text: "test.recent"
    assert_text "Older event"
    click_link "Older event"
    assert_selector "dd", text: "test.old"
    assert_no_link "Older event"
    click_link "Newer event"
    assert_selector "dd", text: "test.recent"
  end

  test "the subject's link in a row's sentence is reached with Tab and pressed with Enter" do
    post = create_post(title: "Spare room")
    event = Audit::Event.create!(action: "post.published", channel: "admin", user_id: users(:one).id, subject: post, subject_label: "Spare room",
      occurred_at: 30.minutes.ago, last_occurred_at: 30.minutes.ago)
    visit_screen admin_audit_events_path

    link = "#audit_event_#{event.id} a.font-medium[href$='/posts/#{post.id}']"
    time_link = "#audit_event_#{event.id} a.admin-row-link"
    page.execute_script("document.querySelector(#{time_link.to_json}).focus()")
    page.send_keys(:tab)
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{link.to_json})"), "Tab from the row's time did not reach the subject's link"
    page.send_keys(:enter)
    assert_current_path(/\/posts\/#{post.id}/)
  end

  # Below 1280px the shell's top bar stands over the page and every sticky top
  # keeps clear of it (`--admin-top-offset`). A band is held inside its own
  # day's section, so the next day's band pushes it out as that day arrives.
  test "a day's band stays under the top bar while its rows scroll, and gives way to the next day's" do
    post = Current.set(actor: users(:one), channel: :admin) { create_post(title: "Linked subject", published: false) }
    now = Time.current
    24.times { |i| Audit::Event.create!(action: "test.today", channel: "admin", user_id: users(:one).id, subject_label: "Today #{i}", occurred_at: now - (i + 1).seconds, last_occurred_at: now - (i + 1).seconds) }
    noon = now.yesterday.change(hour: 12)
    24.times { |i| Audit::Event.create!(action: "test.yesterday", channel: "admin", user_id: users(:one).id, subject_label: "Yesterday #{i}", occurred_at: noon - i.minutes, last_occurred_at: noon - i.minutes) }

    at_window(1100, height: 700) do
      visit_screen admin_audit_events_path
      created = Audit::Event.find_by!(action: "post.created", subject: post)
      assert_selector "#audit_event_#{created.id} p a", text: "Linked subject"
      assert_selector "[data-audit-days] > section > h2", minimum: 2

      measure = lambda do
        page.evaluate_script(<<~JS)
          (() => {
            const bands = [...document.querySelectorAll("[data-audit-days] > section > h2")].map((h) => h.getBoundingClientRect())
            const bar = document.querySelector(".admin-top-bar").getBoundingClientRect()
            const link = document.querySelector("#audit_event_#{created.id} p a").getBoundingClientRect()
            const first = bands[0]
            const onBand = document.elementFromPoint(first.left + 8, first.top + first.height / 2)
            const onLink = document.elementFromPoint(link.left + link.width / 2, link.top + link.height / 2)
            const onBar = document.elementFromPoint(first.left + 8, bar.top + bar.height / 2)
            return {
              bands: bands.map((r) => [r.top, r.bottom]), barBottom: bar.bottom, linkMiddle: link.top + link.height / 2,
              onBand: !!onBand?.closest("[data-audit-days] > section:first-child > h2"),
              onLink: onLink?.closest("h2, a")?.tagName, onBar: !!onBar?.closest(".admin-top-bar")
            }
          })()
        JS
      end
      scroll_to_row = ->(selector, below:) { page.execute_script("window.scrollBy(0, document.querySelector(#{selector.to_json}).getBoundingClientRect().top - #{below})") }

      # Today's first row, the linked one, scrolled up under the band.
      at_rest = measure.call
      scroll_to_row.call("#audit_event_#{created.id}", below: at_rest["barBottom"])
      stuck = measure.call
      assert_in_delta stuck["barBottom"], stuck["bands"][0][0], 1, "today's band stands right under the top bar: #{stuck}"
      assert stuck["onBand"], "the band is on top where it is stuck: #{stuck}"
      assert stuck["onBar"], "the top bar stays over the page: #{stuck}"
      assert_operator stuck["linkMiddle"], :<, stuck["bands"][0][1], "the linked subject has scrolled under the band: #{stuck}"
      assert_equal "H2", stuck["onLink"], "the band covers a row's raised subject link: #{stuck}"

      # Halfway into yesterday: today's band has given way, yesterday's is stuck.
      yesterday = Audit::Event.where(action: "test.yesterday").order(last_occurred_at: :desc).fifth
      scroll_to_row.call("#audit_event_#{yesterday.id}", below: stuck["barBottom"])
      later = measure.call
      assert_in_delta later["barBottom"], later["bands"][1][0], 1, "yesterday's band stands under the top bar: #{later}"
      assert_operator later["bands"][0][1], :<=, later["barBottom"] + 0.5, "today's band has scrolled away with its day: #{later}"
    end
  end
end
