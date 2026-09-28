require "test_helper"

class Posts::SaveTest < ActiveSupport::TestCase
  test "creates a post with translations in several languages" do
    result = Posts::Save.call(attributes: { content_type: "blog" },
      translations: { "en" => { title: "Hello", body: rich_doc("Hi") }, "de" => { title: "Hallo" } })

    assert result.ok?
    assert_equal "Hallo", result.record.title(locale: :de)
    assert_equal "hello", result.record.slug(locale: :en)
    assert_equal rich_doc("Hi"), result.record.reload.body_document(locale: "en").to_h
  end

  test "a body given as a JSON string is parsed into the locale's document" do
    result = Posts::Save.call(attributes: { content_type: "blog" },
      translations: { "de" => { title: "Hallo", body: rich_doc("Text").to_json } })

    assert result.ok?, result.errors.inspect
    assert_equal rich_doc("Text"), result.record.reload.body_document(locale: "de").to_h
    assert result.record.body_document(locale: "en").blank?
  end

  test "an invalid body document fails with an error on body and saves nothing" do
    post = create_post(title: "Hello")
    post.update!(body: rich_doc("Kept"))

    result = Posts::Save.call(post, translations: { "en" => { body: { "type" => "paragraph" } } })

    assert_not result.ok?
    assert result.record.errors[:body].any?
    assert_equal rich_doc("Kept"), post.reload.body_document(locale: "en").to_h
  end

  test "re-publishing a live post keeps its date; scheduled goes live now" do
    live = Post.create!(content_type: :blog, title: "Live", published_at: 3.days.ago)
    original = live.published_at
    Posts::Save.call(live, attributes: { published: true })
    assert_in_delta original, live.reload.published_at, 1

    scheduled = Post.create!(content_type: :blog, title: "Later", published_at: 1.day.from_now)
    Posts::Save.call(scheduled, attributes: { published: true })
    assert scheduled.reload.live?
  end

  test "published_at wins over published and false unpublishes" do
    post = Post.create!(content_type: :blog, title: "P", published_at: 1.day.ago)
    at = 2.days.from_now.change(usec: 0)
    Posts::Save.call(post, attributes: { published: true, published_at: at })
    assert_equal at, post.reload.published_at

    Posts::Save.call(post, attributes: { published: false })
    assert_nil post.reload.published_at
  end

  test "tag names are found or created case-insensitively" do
    Tag.create!(name: "rails")
    result = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ " Rails ", "ruby" ] },
      translations: { "en" => { title: "Tagged" } })
    assert_equal %w[rails ruby], result.record.tags.map(&:name).sort
    assert_equal 1, Tag.where(name: "rails").count
  end

  test "invalid input comes back as a failed result, nothing saved" do
    result = Posts::Save.call(attributes: { content_type: "nope" }, translations: { "en" => { title: "X" } })
    assert_not result.ok?
    assert result.errors.any? { |message| message.match?(/content type/i) }
    assert_equal 0, Post.count
  end

  # `@post.tags =` on an already-persisted post (unlike a new, unsaved one)
  # writes the join rows immediately rather than waiting for `save` to
  # autosave them -- so a failed save on an *update* needs its own coverage
  # to prove that write still lands inside `call`'s transaction and rolls
  # back with everything else, rather than quietly surviving a failed
  # Result.
  test "tag assignment on a persisted post rolls back when the save fails" do
    created = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "a" ] },
      translations: { "en" => { title: "Tagged Post" } })
    assert created.ok?
    post = created.record

    result = Posts::Save.call(post, attributes: { tag_names: [ "b" ] }, translations: { "en" => { title: "" } })

    assert_not result.ok?
    assert_equal [ "a" ], post.reload.tags.map(&:name)
    assert_not Tag.exists?(name: "b")
  end
end
