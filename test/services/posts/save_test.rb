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

  # Related posts (design spec §6.1): `related_post_ids` is the complete
  # list of this post's *forward* relations (`post_relations`) -- whatever
  # it names is kept or added, whatever it leaves out is removed.
  test "related_post_ids replaces the post's forward relations" do
    post = create_post(title: "A")
    kept = create_post(title: "B")
    dropped = create_post(title: "C")
    added = create_post(title: "D")
    PostRelation.create!(post: post, related_post: kept)
    PostRelation.create!(post: post, related_post: dropped)

    result = Posts::Save.call(post, attributes: { related_post_ids: [ kept.id.to_s, added.id.to_s ] })

    assert result.ok?, result.errors.inspect
    assert_equal [ kept.id, added.id ].sort, post.post_relations.pluck(:related_post_id).sort
  end

  test "related_post_ids ignores the post itself and blank entries" do
    post = create_post(title: "A")
    other = create_post(title: "B")

    result = Posts::Save.call(post, attributes: { related_post_ids: [ "", post.id, other.id ] })

    assert result.ok?, result.errors.inspect
    assert_equal [ other.id ], post.post_relations.pluck(:related_post_id)
  end

  test "an empty related_post_ids clears every forward relation" do
    post = create_post(title: "A")
    PostRelation.create!(post: post, related_post: create_post(title: "B"))

    result = Posts::Save.call(post, attributes: { related_post_ids: [] })

    assert result.ok?
    assert_empty post.post_relations.reload
  end

  test "a missing related_post_ids key leaves the relations alone" do
    post = create_post(title: "A")
    other = create_post(title: "B")
    PostRelation.create!(post: post, related_post: other)

    result = Posts::Save.call(post, translations: { "en" => { title: "A2" } })

    assert result.ok?
    assert_equal [ other.id ], post.post_relations.pluck(:related_post_id)
  end

  test "unknown related post ids fail with an error and change nothing" do
    post = create_post(title: "A")
    other = create_post(title: "B")
    PostRelation.create!(post: post, related_post: other)

    result = Posts::Save.call(post, attributes: { related_post_ids: [ other.id, 0, "nope" ] },
      translations: { "en" => { title: "Renamed" } })

    assert_not result.ok?
    assert result.record.errors[:related_post_ids].any?
    assert_equal [ other.id ], post.post_relations.reload.pluck(:related_post_id)
    assert_equal "A", post.reload.title(locale: :en)
  end

  # Relations are read as undirected (`Post#all_related_posts`): a post
  # that already points at this one is already related, so naming it here
  # is a no-op rather than a reverse-pair validation failure.
  test "an id already related in the opposite direction is left as it is" do
    post = create_post(title: "A")
    other = create_post(title: "B")
    PostRelation.create!(post: other, related_post: post)

    result = Posts::Save.call(post, attributes: { related_post_ids: [ other.id ] })

    assert result.ok?, result.errors.inspect
    assert_empty post.post_relations.reload
    assert_equal [ other.id ], post.all_related_posts.pluck(:id)
  end

  test "related_post_ids works when creating a post" do
    other = create_post(title: "B")

    result = Posts::Save.call(attributes: { content_type: "blog", related_post_ids: [ other.id ] },
      translations: { "en" => { title: "New" } })

    assert result.ok?, result.errors.inspect
    assert_equal [ other.id ], result.record.post_relations.pluck(:related_post_id)
  end
end
