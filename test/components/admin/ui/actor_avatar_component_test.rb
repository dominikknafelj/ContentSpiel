require "test_helper"

# `Admin::Ui::ActorAvatarComponent`: the mark beside an audit sentence, one
# per kind of actor, always in a 28px slot and hidden from a screen reader.
class Admin::Ui::ActorAvatarComponentTest < ViewComponent::TestCase
  Actor = Audit::Sentence::Actor

  def actor(you: false, user: nil, user_id: nil, none: false) = Actor.new(you:, user:, user_id:, via_label: nil, none:)

  test "user: anyone else is the 28px avatar in the other tone, with two letters of their name" do
    user = User.new(name: "Ada Lovelace", email_address: "ada@example.com")
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(user: user, user_id: 7))

    assert_selector "span.size-7.bg-people-tint[aria-hidden='true']", exact_text: PersonName.initials(PersonName.of(user))
  end

  test "own: the viewer's own event is the filled circle" do
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(you: true, user: users(:one), user_id: users(:one).id))

    assert_selector "span.size-7.bg-people.text-surface[aria-hidden='true']", exact_text: PersonName.initials(PersonName.of(users(:one)))
  end

  test "deleted_user: an empty circle in the away tone, since an event records no name" do
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(user_id: 42))

    assert_selector "span.size-7.border-dashed.border-field-line.text-meta[aria-hidden='true']", exact_text: ""
  end

  test "system: not a person, so the neutral settings icon chip in the slot, no circle" do
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor)

    assert_selector "span.size-7[aria-hidden='true'] svg"
    assert_no_selector ".rounded-full"
  end

  test "nobody: an empty slot of the same width, so the sentences stay aligned" do
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(none: true))

    assert_selector "span.size-7[aria-hidden='true']", exact_text: ""
    assert_no_selector "svg"
    assert_no_selector ".rounded-full"
  end
end
