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

  test "a tag name over the limit fails the save and creates nothing; inner whitespace collapses" do
    result = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "fine", "x" * (Tag::MAX_NAME_LENGTH + 1) ] },
      translations: { "en" => { title: "Tagged" } })

    assert_not result.ok?
    assert result.errors.any? { |message| message.include?("longer than #{Tag::MAX_NAME_LENGTH} characters") }
    assert_not Tag.exists?(name: "fine")

    ok = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "Two   words" ] }, translations: { "en" => { title: "Spaced" } })
    assert_equal [ "two words" ], ok.record.tags.map(&:name)
  end

  # A tag stored before the length limit (or by a console) is reused as it is:
  # only a name that would be CREATED can be refused.
  test "a post carrying a legacy over-long tag still saves, and the tag is reused" do
    legacy = Tag.new(name: "l" * 60).tap { |tag| tag.save!(validate: false) }
    post = create_post(title: "Legacy")
    post.tags << legacy

    result = Posts::Save.call(post, attributes: { tag_names: [ "l" * 60, "extra" ] }, translations: { "en" => { title: "Edited" } })

    assert result.ok?, result.errors.inspect
    assert_equal [ "extra", "l" * 60 ], result.record.tags.map(&:name).sort
    assert_equal 1, Tag.where(name: "l" * 60).count
    assert_not Tag.exists?(name: "l" * 60 + "x")
  end

  test "a new over-long name is still refused when an existing long tag is resent" do
    Tag.new(name: "l" * 60).save!(validate: false)

    result = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "l" * 60, "n" * 60 ] }, translations: { "en" => { title: "Mixed" } })

    assert_not result.ok?
    assert_equal 1, Tag.where(name: "l" * 60).count
    assert_not Tag.exists?(name: "n" * 60)
  end

  test "an existing tag with inner double spaces is matched on its exact name, not duplicated" do
    spaced = Tag.create!(name: "two  words")

    result = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "Two  Words" ] }, translations: { "en" => { title: "Spaced" } })

    assert_equal [ spaced.id ], result.record.tags.map(&:id)
    assert_equal 1, Tag.count
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

  # Media library design spec §5.1: the write path keeps `media_usages` in
  # step with the body, and a destroyed post leaves no rows behind.
  test "saving a post indexes its body images and destroying it removes them" do
    first = create_media_asset
    second = create_media_asset
    post = Posts::Save.call(attributes: { content_type: "blog" }, translations: {
      "en" => { title: "Pictures", body: rich_doc("::image{asset=\"#{first.id}\"}") },
      "de" => { title: "Bilder", body: rich_doc("::image{asset=\"#{second.id}\"}") }
    }).record

    usages = -> { Media::Usage.where(owner_type: "Post", owner_id: post.id).order(:locale).pluck(:media_asset_id, :role, :locale) }
    assert_equal [ [ second.id, "rich_text", "de" ], [ first.id, "rich_text", "en" ] ], usages.call

    # Review Focus 2: removing the image from `de` only drops that row.
    assert Posts::Save.call(post, translations: { "de" => { body: rich_doc("Keine Bilder") } }).ok?
    assert_equal [ [ first.id, "rich_text", "en" ] ], usages.call
    assert second.reload.usages.none?

    assert delete_for_good(post)
    assert_empty usages.call
  end

  # Final fix wave (M1): an image deleted after the body validated and
  # after `UsageIndex` checked it, before its usage row is written, hits
  # the FK on `media_usages` -- a validation failure, not a 500, and the
  # post is unchanged.
  test "a body image deleted before its usage row is written fails validation" do
    asset = create_media_asset
    post = create_post(title: "Pictures")
    insert_all = Media::Usage.method(:insert_all)
    racing = ->(rows, **options) { Media::Asset.where(id: asset.id).delete_all && insert_all.call(rows, **options) }

    result = with_singleton_override(Media::Usage, :insert_all, racing) do
      Posts::Save.call(post, translations: { "en" => { title: "Changed", body: rich_doc("::image{asset=\"#{asset.id}\"}") } })
    end

    assert_not result.ok?
    assert_equal [ "Body has an image that doesn't exist" ], result.errors
    assert_equal "Pictures", post.reload.title
  end

  # Only a `media_assets` FK is answered as a missing image; any other
  # refused FK (a tag or author deleted mid-save) must not be misreported
  # as "Body has an image that doesn't exist" -- it propagates.
  test "a foreign key violation unrelated to media is not reported as a missing image" do
    post = create_post(title: "Pictures")
    unrelated = ->(*) { raise ActiveRecord::InvalidForeignKey, "insert or update on table \"taggings\" violates foreign key constraint \"fk_rails_tag\"" }

    assert_raises(ActiveRecord::InvalidForeignKey) do
      with_singleton_override(Media::UsageIndex, :refresh, unrelated) do
        Posts::Save.call(post, translations: { "en" => { title: "Changed" } })
      end
    end
    assert_equal "Pictures", post.reload.title
  end

  # --- `attributes:` is an allow-list ----------------------------------------
  #
  # Putting a post in the trash is `Trash::Move`'s to do, with the delete
  # right; no caller passes these keys, and one that ever did must fail
  # loudly rather than trash (or backdate) a post on the strength of
  # `posts.edit`.

  test "attributes that belong to another service are an ArgumentError, and nothing is written" do
    post = create_post(title: "Stays put")
    before = post.reload.attributes

    forbidden = {
      trashed_at: Time.current, trashed_by_id: users(:one).id, trashed_by: users(:one), id: 1, created_at: 1.year.ago,
      updated_at: 1.year.ago, translation_sources: {}, title: "Smuggled", slug: "smuggled", body: {}, tags: [], related_posts: []
    }
    forbidden.each do |key, value|
      error = assert_raises(ArgumentError, "#{key} was accepted") { Posts::Save.call(post, attributes: { key => value, published: true }) }
      assert_includes error.message, key.to_s
      assert_raises(ArgumentError, "#{key} was accepted as a String key") { Posts::Save.call(post, attributes: { key.to_s => value }) }
      assert_raises(ArgumentError, "#{key} was accepted on create") { Posts::Save.call(attributes: { content_type: "blog", key => value }, translations: { "en" => { title: "New" } }) }
    end

    assert_equal before, post.reload.attributes
    assert_not post.trashed?
  end

  test "every attribute the service is meant to take is still taken" do
    other = create_post(title: "Related")
    result = as_owner do
      Posts::Save.call(attributes: { content_type: "blog", author_id: users(:two).id, published_at: 1.day.from_now, tag_names: [ "ruby" ],
        fields: {}, related_post_ids: [ other.id.to_s ] }, translations: { "en" => { title: "Allowed" } })
    end
    assert result.ok?, result.errors.to_sentence
    assert_equal users(:two).id, result.record.author_id
    assert_equal [ "ruby" ], result.record.tags.map(&:name)
    assert_equal [ other ], result.record.related_posts.to_a

    assert as_owner { Posts::Save.call(result.record, attributes: { published: true }) }.ok?
    assert result.record.reload.live?
  end
end
