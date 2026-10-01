require "test_helper"

# Site time zone (dashboard spec §5): CS Studio shows and parses times in
# `SiteSetting#time_zone`; storage stays UTC.
class Admin::TimeZoneTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    sign_in_as users(:one)
    @post = Current.set(actor: users(:one)) { create_post(title: "Later", published: false) }
  end

  def schedule_path_for(post) = schedule_admin_post_path(post)

  test "a schedule time is read as site-local and stored as UTC" do
    post schedule_path_for(@post), params: { published_at: "2026-11-02T09:00" }
    assert_equal Time.utc(2026, 11, 2, 8, 0), @post.reload.published_at   # CET = UTC+1
  end

  test "a scheduled time shows in site-local time" do
    # Picked inside CEST (last Sunday of March - last Sunday of October) and
    # far enough out that the suite stays green regardless of which day it
    # actually runs on -- the scheduled-time input only shows `published_at`
    # at all while the post's own status is "scheduled" (`Post#status`,
    # `PostFormComponent#scheduled_at_input_value`), so this has to stay in
    # the future.
    @post.update_columns(published_at: Time.utc(2030, 7, 1, 7, 30))      # CEST = UTC+2
    get admin_post_path(@post)
    assert_match "2030-07-01T09:30", response.body                       # the datetime-local value
  end

  test "a time in the spring-forward gap is saved, not a 500" do
    post schedule_path_for(@post), params: { published_at: "2027-03-28T02:30" }
    assert_response :redirect
    assert @post.reload.published_at.present?
  end

  test "audit log and trash times render in the site zone" do
    travel_to Time.utc(2026, 7, 1, 7, 30) do # CEST = UTC+2 -> 09:30 local
      Current.set(actor: users(:one)) do
        Posts::Save.call(@post, translations: { Locales.default => { title: "Later, edited" } })
      end
    end
    event = Audit::Event.find_by!(subject: @post, action: "post.updated")

    get admin_audit_events_path
    assert_response :success
    assert_match "Jul 1, 2026 09:30", response.body

    get admin_audit_event_path(event)
    assert_response :success
    assert_match "July 1, 2026 at 09:30", response.body

    Current.set(actor: users(:one)) { Trash::Move.call(@post) }
    @post.reload.update_columns(trashed_at: Time.utc(2026, 7, 1, 7, 30))

    get admin_trash_path
    assert_response :success
    assert_match "Jul 1, 2026 09:30", response.body
  end
end
