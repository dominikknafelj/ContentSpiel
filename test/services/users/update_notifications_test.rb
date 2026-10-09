require "test_helper"

# The two per-person settings for a mention (notes spec D18, D19, §6.4).
class Users::UpdateNotificationsTest < ActiveSupport::TestCase
  test "the defaults: sound on, desktop off" do
    assert_equal [ true, false ], [ users(:reader).notes_sound, users(:reader).notes_desktop ]
  end

  test "a person changes their own two settings, and it is audited as their account" do
    result = as(users(:reader)) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: true) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ false, true ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
    event = Audit::Event.order(:id).last
    assert_equal [ "user.updated", "User", users(:reader).id ], [ event.action, event.subject_type, event.subject_id ]
    # What was switched, old to new, and the account as it now stands.
    assert_equal({ "notes_sound" => [ true, false ], "notes_desktop" => [ false, true ] }, event.field_changes)
    assert_equal [ false, true ], event.snapshot.values_at("notes_sound", "notes_desktop")
  end

  test "a save that changes nothing is still an ordinary success" do
    result = as(users(:reader)) { Users::UpdateNotifications.call(users(:reader), sound: true, desktop: false) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ true, false ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
  end

  test "nobody changes someone else's, not even a user manager, and a token never does" do
    assert_predicate as(users(:two)) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: false) }, :denied?
    token, = ApiToken.generate!(users(:reader), group: access_control_groups(:admin))
    assert_predicate as(token, channel: :mcp) { Users::UpdateNotifications.call(users(:reader), sound: false, desktop: false) }, :denied?
    assert users(:reader).reload.notes_sound
  end
end
