require "test_helper"

# `Audit::ChangeSince` names who made a record stale; the banner and the
# editors' bar both read it.
class Audit::ChangeSinceTest < ActiveSupport::TestCase
  setup do
    @viewer = users(:one)
    @other = users(:two)
    @subject = users(:reader)
    @base = Time.zone.parse("2026-10-05 10:00:00")
  end

  def event(action, user, at, subject: @subject)
    Audit::Event.create!(action: action, user_id: user&.id, subject_type: subject.class.base_class.name, subject_id: subject.id,
      occurred_at: at, last_occurred_at: at)
  end

  def change(since: @base) = Audit::ChangeSince.for(@subject, since: since, viewer: @viewer)

  test "a sign-in or sign-out of the user is no change" do
    event("session.created", @subject, @base + 1.minute)
    event("session.destroyed", @subject, @base + 2.minutes)

    assert_nil change
  end

  test "a refusal is no change" do
    event("access.denied", @other, @base + 1.minute)

    assert_nil change
  end

  test "someone else's newest change is preferred over a newer one of the viewer's own" do
    theirs = event("user.updated", @other, @base + 1.minute)
    event("user.updated", @viewer, @base + 2.minutes)

    result = change
    assert_equal theirs, result.event
    assert_not result.own
  end

  test "a change by the viewer's own other tab says so" do
    mine = event("user.updated", @viewer, @base + 1.minute)

    result = change
    assert_equal mine, result.event
    assert result.own
  end

  test "no event at all is nil" do
    assert_nil change
    assert_nil change(since: nil)
  end

  test "an event at or just past the carried base is the change the form loaded" do
    event("user.updated", @other, @base)
    event("user.updated", @other, @base + Audit::ChangeSince::SLACK)

    assert_nil change
    assert_equal "user.updated", change(since: @base - 1.minute).event.action
  end

  test "an event about another record is not named" do
    event("group.updated", @other, @base + 1.minute, subject: access_control_groups(:author))

    assert_nil change
  end

  test "a note is not a change to the record" do
    page = create_page(title: "Pricing")
    base = page.reload.updated_at
    travel_to(1.minute.from_now) { as(users(:two)) { Notes::Start.call(page, body: "A question") } }

    assert_nil Audit::ChangeSince.for(page, since: base, viewer: users(:one))
  end
end
