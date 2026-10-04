require "test_helper"

# The Schedule dialog (design pass round 2, handoff §10 B21).
class Admin::EditorScreen::ScheduleDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_dialog(record, error: nil)
    as(users(:one), channel: :admin) { render_inline(Admin::EditorScreen::ScheduleDialogComponent.new(record: record, error: error)) }
  end

  test "a draft: titled, a datetime field defaulting to tomorrow 09:00 in the site zone, the zone line, no Remove" do
    site_settings(:default).update!(time_zone: "Berlin")
    page_record = create_page(title: "Later", published: false)
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      render_dialog(page_record)
    end
    id = "schedule-page-#{page_record.id}"
    assert_selector "dialog##{id}[data-dialog-width=form_narrow]", visible: :all
    assert_selector "##{id}-title", text: "Schedule publishing", visible: :all
    assert_selector "label", text: "Date and time", visible: :all
    assert_selector "input[type=datetime-local][name=published_at][value='2026-10-05T09:00'][min='2026-10-04T12:00']", visible: :all
    assert_selector "dialog##{id}", text: "Berlin time (GMT+2), the site’s time zone.", visible: :all
    assert_no_selector "button", text: "Remove schedule", visible: :all
    assert_no_selector "[role=alert]", visible: :all
    assert_no_selector "dialog[data-admin--dialog-open-on-load]", visible: :all
    assert_selector "form[action='/cs-studio/pages/#{page_record.id}/schedule'][data-turbo-frame='_top'][novalidate]", visible: :all
  end

  test "a scheduled record: the field shows its schedule in site time, and Remove schedule is a ghost submit at the left" do
    site_settings(:default).update!(time_zone: "Berlin")
    post_record = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post_record, attributes: { published_at: Time.utc(2030, 1, 15, 8, 30) }) }
    render_dialog(post_record.reload)
    id = "schedule-post-#{post_record.id}"
    assert_selector "input[name=published_at][value='2030-01-15T09:30']", visible: :all
    assert_selector "dialog##{id}", text: "Berlin time (GMT+1), the site’s time zone.", visible: :all
    assert_selector "dialog##{id} footer form.mr-auto button[type=submit]", text: "Remove schedule", visible: :all
    assert_selector "dialog##{id} footer button.bg-accent[form='#{id}-form']", text: "Schedule", visible: :all
    assert_selector "dialog##{id} footer button", text: "Cancel", visible: :all
  end

  test "an error shows as an alert, marks the field invalid and asks to be opened on load" do
    page_record = create_page(title: "Later", published: false)
    render_dialog(page_record, error: "Pick a time in the future.")
    assert_selector "dialog[data-admin--dialog-open-on-load] [role=alert]", text: "Pick a time in the future.", visible: :all
    assert_selector "input[name=published_at][aria-invalid=true]", visible: :all
  end

  test "the zone line: an offset with minutes, UTC, and a zone name that already says Time or carries parentheses" do
    { "Kolkata" => "Kolkata time (GMT+5:30), the site’s time zone.",
      "UTC" => "UTC (GMT+0), the site’s time zone." }.each do |zone, line|
      site_settings(:default).update!(time_zone: zone)
      render_dialog(create_page(title: "Zone #{zone}", published: false))
      assert_text line, normalize_ws: true
    end
    site_settings(:default).update!(time_zone: "Eastern Time (US & Canada)")
    render_dialog(create_page(title: "Later two", published: false))
    assert_selector "dialog", text: /Eastern Time \(US & Canada\), GMT-[45], the site’s time zone\./, visible: :all
    assert_no_selector "dialog", text: /\(US & Canada\) \(GMT/, visible: :all
  end

  test "the schedule form has exactly one submit button (Enter in the date field must schedule, never remove)" do
    post_record = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post_record, attributes: { published_at: 3.days.from_now }) }
    render_dialog(post_record.reload)
    id = "schedule-post-#{post_record.id}"
    submits = page.all("button[type=submit][form='#{id}-form'], ##{id}-form button, ##{id}-form input[type=submit]", visible: :all)
    assert_equal 1, submits.size
    assert_equal "Schedule", submits.first.text(:all).strip
    assert_selector "dialog##{id} footer form:not([method=dialog]) input[name=remove][value='1'][type=hidden]", visible: :all
    assert_no_selector "##{id}-form input[name=remove]", visible: :all
  end

  test "after a refusal the typed value comes back, blank stays blank, junk falls back to the default, and it is escaped" do
    page_record = create_page(title: "Later", published: false)
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      {
        "2020-01-01T09:00" => "2020-01-01T09:00",
        "" => "",
        "soon" => "2026-10-05T09:00",
        "\"><script>x</script>" => "2026-10-05T09:00"
      }.each do |typed, shown|
        as(users(:one), channel: :admin) do
          render_inline(Admin::EditorScreen::ScheduleDialogComponent.new(record: page_record, error: "Pick a time in the future.", value: typed))
        end
        assert_selector "input[name=published_at][value='#{shown}']", visible: :all
        assert_no_selector "script", visible: :all
      end
    end
  end

  test "without an error the value is ignored" do
    page_record = create_page(title: "Later", published: false)
    as(users(:one), channel: :admin) do
      render_inline(Admin::EditorScreen::ScheduleDialogComponent.new(record: page_record, value: "2020-01-01T09:00"))
    end
    assert_no_selector "input[value='2020-01-01T09:00']", visible: :all
  end

  test "only a Page or a Post" do
    assert_raises(ArgumentError) { Admin::EditorScreen::ScheduleDialogComponent.new(record: Tag.new) }
  end
end
