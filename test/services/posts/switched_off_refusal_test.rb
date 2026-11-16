require "test_helper"

# A post whose type is switched off (or no longer declared) is kept whole and
# changed by nobody: every write service answers a 422 failure with one
# sentence, before the rights are asked, so nothing is denied and nothing is
# written or audited.
class Posts::SwitchedOffRefusalTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  SERVICES = {
    "Posts::Save" => ->(post) { Posts::Save.call(post, attributes: {}, translations: { "en" => { title: "Changed" } }) },
    "Publishing::PublishChanges" => ->(post) { Publishing::PublishChanges.call(post) },
    "Publishing::DiscardChanges" => ->(post) { Publishing::DiscardChanges.call(post) },
    "Publishing::CancelScheduledChange" => ->(post) { Publishing::CancelScheduledChange.call(post) },
    "Translations::Confirm" => ->(post) { Translations::Confirm.call(post, field: "title", locale: "de") }
  }.freeze

  SENTENCE = "Resume entry is switched off. Switch it on in Settings to change this post."

  def dormant_post
    switch_on_content_types("blog", "resume_entry")
    post = create_post(title: "Role", content_type: "resume_entry")
    switch_on_content_types("blog")
    post.reload
  end

  test "each write service refuses a dormant post with the sentence, writing and auditing nothing" do
    post = dormant_post

    SERVICES.each do |name, call|
      rows = Post.where(id: post.id).pick(:updated_at, :title)
      versions = Publishing::Version.count
      events = Audit::Event.count

      result = call.call(post)

      assert_not result.ok?, name
      assert_not result.denied?, name
      assert_equal [ SENTENCE ], result.errors, name
      assert_equal rows, Post.where(id: post.id).pick(:updated_at, :title), name
      assert_equal versions, Publishing::Version.count, name
      assert_equal events, Audit::Event.count, name
    end
  end

  test "a new post of a switched-off type is refused" do
    switch_on_content_types("blog")

    assert_no_difference [ "Post.count", "Audit::Event.count" ] do
      result = Posts::Save.call(attributes: { content_type: "resume_entry" }, translations: { "en" => { title: "New" } })

      assert_equal [ SENTENCE ], result.errors
    end
  end

  test "an undeclared type's stored name is the sentence's" do
    post = create_post(title: "Gone")
    post.update_columns(content_type: "retired_type")

    result = Posts::Save.call(post.reload, translations: { "en" => { title: "Changed" } })

    assert_equal [ "retired_type is switched off. Switch it on in Settings to change this post." ], result.errors
  end

  test "the trash services move, restore and purge a dormant post" do
    post = dormant_post

    assert Trash::Move.call(post).ok?
    assert post.reload.trashed?

    assert Trash::Restore.call(post).ok?
    assert_not post.reload.trashed?
    assert_not post.type_switched_on?
    assert_nil PublicSite::Paths.current_path(post, Locales.default)

    assert Trash::Move.call(post.reload).ok?
    assert Trash::Purge.call(post.reload).ok?
    assert_not Post.exists?(post.id)
  end
end
