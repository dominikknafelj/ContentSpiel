require "test_helper"

class Users::UpdateProfileTest < ActiveSupport::TestCase
  test "a user changes their own name, audited as user.updated" do
    user = users(:two)
    Current.set(actor: user, channel: :admin) do
      result = Users::UpdateProfile.call(user, name: "Grace Hopper")
      assert result.ok?
    end
    assert_equal "Grace Hopper", user.reload.name
    assert_equal "user.updated", Audit::Event.order(:id).last.action
    assert_equal [ nil, "Grace Hopper" ], Audit::Event.order(:id).last.field_changes["name"]
  end

  test "changing someone else's name is refused and logged as a denial" do
    actor, other = users(:two), users(:one)
    Current.set(actor: actor, channel: :admin) do
      assert_not Users::UpdateProfile.call(other, name: "Mallory").ok?
    end
    assert_nil other.reload.name
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "a user with a short legacy password can still change their name" do
    user = users(:two) # fixture digest is for the 8-character "password"
    Current.set(actor: user, channel: :admin) do
      assert Users::UpdateProfile.call(user, name: "Still Fine").ok?
    end
  end

  test "a too-long name fails without an event" do
    user = users(:two)
    before = Audit::Event.count
    Current.set(actor: user, channel: :admin) do
      assert_not Users::UpdateProfile.call(user, name: "a" * 121).ok?
    end
    assert_equal before, Audit::Event.count
  end

  # --- the two notes settings (notes spec D18, D19, §6.4; handoff decision 13) ------

  test "the defaults: sound on, desktop off" do
    assert_equal [ true, false ], [ users(:reader).notes_sound, users(:reader).notes_desktop ]
  end

  test "the name and the two notes settings are one save and one event" do
    user = users(:reader)
    before = Audit::Event.count
    result = as(user) { Users::UpdateProfile.call(user, name: "Ada", notes_sound: false, notes_desktop: true) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "Ada", false, true ], user.reload.then { |saved| [ saved.name, saved.notes_sound, saved.notes_desktop ] }
    assert_equal before + 1, Audit::Event.count
    event = Audit::Event.order(:id).last
    assert_equal [ "user.updated", "User", user.id ], [ event.action, event.subject_type, event.subject_id ]
    # What was changed, old to new, and the account as it now stands.
    assert_equal({ "name" => [ nil, "Ada" ], "notes_sound" => [ true, false ], "notes_desktop" => [ false, true ] }, event.field_changes)
    assert_equal [ false, true ], event.snapshot.values_at("notes_sound", "notes_desktop")
  end

  test "a setting that is not given is left as it is" do
    user = users(:reader)
    user.update!(notes_sound: false, notes_desktop: true)

    assert as(user) { Users::UpdateProfile.call(user, name: "Ada") }.ok?
    assert_equal [ false, true ], user.reload.then { |saved| [ saved.notes_sound, saved.notes_desktop ] }
    assert as(user) { Users::UpdateProfile.call(user, name: "Ada", notes_desktop: false) }.ok?
    assert_equal [ false, false ], user.reload.then { |saved| [ saved.notes_sound, saved.notes_desktop ] }
  end

  test "a name that is refused takes the settings down with it: nothing is written" do
    user = users(:reader)
    result = as(user) { Users::UpdateProfile.call(user, name: "a" * 121, notes_sound: false, notes_desktop: true) }

    assert_not result.ok?
    assert_equal [ nil, true, false ], user.reload.then { |saved| [ saved.name, saved.notes_sound, saved.notes_desktop ] }
  end

  test "nobody changes someone else's settings, not even a user manager, and a token never does" do
    assert_predicate as(users(:two)) { Users::UpdateProfile.call(users(:reader), name: nil, notes_sound: false, notes_desktop: true) }, :denied?
    token, = ApiToken.generate!(users(:reader), group: access_control_groups(:admin))
    assert_predicate as(token, channel: :mcp) { Users::UpdateProfile.call(users(:reader), name: nil, notes_sound: false, notes_desktop: true) }, :denied?
    assert_equal [ true, false ], users(:reader).reload.then { |saved| [ saved.notes_sound, saved.notes_desktop ] }
  end
end
