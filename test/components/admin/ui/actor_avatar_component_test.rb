require "test_helper"

# `Admin::Ui::ActorAvatarComponent`: the mark of who did or wrote something,
# one per kind of actor, from an audit actor or from a user a note names, in
# a 28px, a 26px or a 22px slot, and hidden from a screen reader.
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

  test "deleted_user: an empty circle with a solid field-line hairline on the surface, since an event records no name" do
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(user_id: 42))

    assert_selector "span.size-7.border.border-field-line.bg-surface[aria-hidden='true']", exact_text: ""
    assert_no_selector ".border-dashed, .bg-people-tint, .text-people"
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

  test "size sm draws the 22px circle in a 22px slot, and an unknown size is refused" do
    user = User.new(name: "Ada Lovelace", email_address: "ada@example.com")
    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(user: user, user_id: 7), size: :sm)
    assert_selector "span.size-\\[22px\\].bg-people-tint[aria-hidden='true']", exact_text: PersonName.initials(PersonName.of(user))
    assert_no_selector ".size-7"

    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(user_id: 42), size: :sm)
    assert_selector "span.size-\\[22px\\].border-field-line[aria-hidden='true']", exact_text: ""

    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor, size: :sm)
    assert_selector "span.size-\\[22px\\][aria-hidden='true'] > span.size-5 svg"

    render_inline Admin::Ui::ActorAvatarComponent.new(actor: actor(none: true), size: :sm)
    assert_selector "span.size-\\[22px\\][aria-hidden='true']", exact_text: ""

    assert_raises(ArgumentError) { Admin::Ui::ActorAvatarComponent.new(actor: actor, size: :xl) }
  end

  test "user form: a note's person is the same circle, two initials from a name or one word, the viewer's own filled" do
    dana = users(:two).tap { |user| user.update!(name: "Dana van Weiss") }

    render_inline Admin::Ui::ActorAvatarComponent.new(user: dana, viewer: dana, size: :sm)
    assert_selector "span.size-\\[22px\\].bg-people.text-surface.rounded-full[aria-hidden='true']", exact_text: "Dv"

    render_inline Admin::Ui::ActorAvatarComponent.new(user: users(:reader), viewer: dana, size: :md)
    assert_selector "span.size-\\[26px\\].bg-people-tint[aria-hidden='true']", exact_text: "re"
    assert_no_selector "span.bg-people"

    render_inline Admin::Ui::ActorAvatarComponent.new(user: dana, size: :md)
    assert_selector "span.size-\\[26px\\].bg-people-tint", exact_text: "Dv"
  end

  test "user form: a deleted user (nil) is the empty circle, never System, and an actor and a user together are refused" do
    render_inline Admin::Ui::ActorAvatarComponent.new(user: nil, viewer: users(:two), size: :md)

    assert_selector "span.size-\\[26px\\].rounded-full.border.border-field-line.bg-surface[aria-hidden='true']", exact_text: ""
    assert_no_selector "svg, span.bg-people, span.bg-people-tint, span.text-people"

    assert_raises(ArgumentError) { Admin::Ui::ActorAvatarComponent.new(actor: actor, user: users(:two)) }
  end

  test "the user form draws exactly what the actor form draws for the same person" do
    ada = users(:one)
    from_actor = render_inline(Admin::Ui::ActorAvatarComponent.new(actor: actor(you: true, user: ada, user_id: ada.id), size: :sm)).to_html
    from_user = render_inline(Admin::Ui::ActorAvatarComponent.new(user: ada, viewer: ada, size: :sm)).to_html

    assert_equal from_actor, from_user
  end
end
