require "test_helper"

class Admin::AuditScreen::SentenceComponentTest < ViewComponent::TestCase
  def sentence(action, viewer: users(:one), route: nil, **attributes)
    event = Audit::Event.new({ action:, channel: "admin", user_id: users(:one).id, subject_label: "Hello", occurred_at: Time.current, last_occurred_at: Time.current }.merge(attributes))
    target = Audit::Sentence::Target.new("Hello", route)
    Audit::Sentence.build(event, viewer:, target:)
  end

  test "You for the viewer, the subject quoted and linked when the sentence has a route" do
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.published", route: Audit::Sentence::Route.new(:admin_post_path, [ 7 ], {})))

    assert_text "You published “Hello”"
    assert_selector "a[href='/cs-studio/posts/7']", text: "Hello"
  end

  test "no route is plain text, never a link" do
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.published"))

    assert_text "You published “Hello”"
    assert_no_selector "a"
  end

  test "another user is named, a token follows via, and the viewer's own token reads You, via" do
    other = sentence("post.created", viewer: users(:two), actor_type: "ApiToken", actor_id: 1, actor_label: "Claude desktop")
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: other)
    assert_text "#{users(:one).display_name} via Claude desktop created “Hello”"

    own = sentence("post.created", actor_type: "ApiToken", actor_id: 1, actor_label: "Claude desktop")
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: own)
    assert_text "You, via Claude desktop created “Hello”"
  end

  test "no user at all is System; a deleted user is named so; a failed sign-in has no actor" do
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.created", user_id: nil))
    assert_text "System created"

    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.created", user_id: 999_999))
    assert_text "a deleted user created"

    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("session.failed", user_id: nil))
    assert_equal "Failed sign-in attempt", page.text.strip
  end

  test "stored text is escaped" do
    event = Audit::Event.new(action: "post.created", channel: "admin", user_id: users(:two).id, actor_type: "ApiToken", actor_id: 1, actor_label: "<i>x</i>",
      occurred_at: Time.current, last_occurred_at: Time.current)
    sentence = Audit::Sentence.build(event, viewer: users(:one), target: Audit::Sentence::Target.new("<script>1</script>", nil))
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence:)

    assert_no_selector "script"
    assert_no_selector "i"
    assert_text "<script>1</script>"
    assert_text "via <i>x</i>"
  end

  # Final fix wave (M3): the one place a sentence's route NAME becomes a call.
  # `Audit::Sentence` only ever builds six; the component checks the name
  # against its own frozen list all the same, so a name from anywhere else is
  # never `public_send` to the helpers -- the subject is then plain text.
  test "each of the six routes a sentence can carry is linked" do
    {
      Audit::Sentence::Route.new(:admin_page_path, [ 7 ], {}) => "/cs-studio/pages/7",
      Audit::Sentence::Route.new(:admin_post_path, [ 7 ], {}) => "/cs-studio/posts/7",
      Audit::Sentence::Route.new(:admin_media_path, [], { selected: 7 }) => "/cs-studio/media?selected=7",
      Audit::Sentence::Route.new(:edit_admin_user_path, [ 7 ], {}) => "/cs-studio/users/7/edit",
      Audit::Sentence::Route.new(:edit_admin_group_path, [ 7 ], {}) => "/cs-studio/groups/7/edit",
      Audit::Sentence::Route.new(:admin_settings_path, [], {}) => "/cs-studio/settings"
    }.each do |route, href|
      render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.published", route:))

      assert_selector "a[href='#{href}']", text: "Hello"
    end
    assert_equal 6, Admin::AuditScreen::SentenceComponent::ROUTES.size
    assert Admin::AuditScreen::SentenceComponent::ROUTES.frozen?
  end

  test "a route name outside the list is never called: the subject is plain text" do
    [ :admin_sign_out_path, :admin_posts_path, :instance_eval, :root_path, "admin_post_path" ].each do |name|
      render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("post.published", route: Audit::Sentence::Route.new(name, [ 7 ], {})))

      assert_no_selector "a"
      assert_text "You published “Hello”"
    end
  end

  test "an answered take-over reads handed over, an unanswered one took over, and neither names a second person" do
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("page.taken_over", metadata: { "from_user_id" => 1, "to_user_id" => 2, "answered" => true }))
    assert_text "You handed over editing “Hello”"

    render_inline Admin::AuditScreen::SentenceComponent.new(sentence: sentence("page.taken_over", metadata: { "from_user_id" => 1, "to_user_id" => 2, "answered" => false }))
    assert_text "You took over editing “Hello”"
  end

  test "a collection is linked where the sentence has a route, and never quoted" do
    upload = Audit::Event.new(action: "media.uploaded", channel: "admin", user_id: users(:one).id, occurred_at: Time.current, last_occurred_at: Time.current)
    sentence = Audit::Sentence.build(upload, viewer: users(:one), target: Audit::Sentence::Target.new(nil, Audit::Sentence.library_route), count: 12)
    render_inline Admin::AuditScreen::SentenceComponent.new(sentence:)

    assert_text "You uploaded 12 images"
    assert_no_text "“"
    assert_selector "a[href='/cs-studio/media']", exact_text: "12 images"
  end
end
