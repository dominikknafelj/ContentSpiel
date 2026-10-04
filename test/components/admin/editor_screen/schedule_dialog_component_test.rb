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
    assert_selector "dialog##{id} footer button[type=submit][name=remove][value='1'][form='#{id}-form'].mr-auto", text: "Remove schedule", visible: :all
    assert_selector "dialog##{id} footer button.bg-accent[form='#{id}-form']", text: "Schedule", visible: :all
    assert_selector "dialog##{id} footer button", text: "Cancel", visible: :all
  end

  test "an error shows as an alert, marks the field invalid and asks to be opened on load" do
    page_record = create_page(title: "Later", published: false)
    render_dialog(page_record, error: "Pick a time in the future.")
    assert_selector "dialog[data-admin--dialog-open-on-load] [role=alert]", text: "Pick a time in the future.", visible: :all
    assert_selector "input[name=published_at][aria-invalid=true]", visible: :all
  end

  test "the zone line names an offset with minutes and a zone whose name already says Time" do
    site_settings(:default).update!(time_zone: "Kolkata")
    render_dialog(create_page(title: "Later", published: false))
    assert_text "Kolkata time (GMT+5:30), the site’s time zone.", normalize_ws: true
    site_settings(:default).update!(time_zone: "Eastern Time (US & Canada)")
    render_dialog(create_page(title: "Later two", published: false))
    assert_text(/Eastern Time \(US & Canada\) \(GMT-[45]\), the site’s time zone\./)
  end

  test "only a Page or a Post" do
    assert_raises(ArgumentError) { Admin::EditorScreen::ScheduleDialogComponent.new(record: Tag.new) }
  end
end
