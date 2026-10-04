require "test_helper"

class Posts::BulkTest < ActiveSupport::TestCase
  # A viewer whose groups hold `posts.read` limited to `content_types` (built
  # as the access-control tests build theirs), with nothing else.
  def scoped_reader(content_types:)
    user = User.create!(email_address: "scoped-#{SecureRandom.hex(3)}@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Scoped #{SecureRandom.hex(3)}")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => content_types })
    AccessControl::Grant.create!(group: group, permission: "posts.delete", scope: { "content_types" => content_types })
    AccessControl::Membership.create!(group: group, user: user)
    user
  end

  test "a mixed selection: each permitted post is acted on once, the rest are reported, nothing is silent" do
    mine = create_post(title: "Mine", published: false)
    theirs = create_post(title: "Theirs", published: false)
    trashed = create_post(title: "Gone", published: false)
    as_owner { Trash::Move.call(trashed) }

    result = as(users(:one), channel: :admin) do
      Posts::Bulk.call(action: "publish", ids: [ mine.id, theirs.id, trashed.id, 999_999, mine.id ])
    end
    assert_equal [ mine, theirs ].sort_by(&:id), result.done.sort_by(&:id)
    assert_empty result.refused
    assert_equal 2, result.not_found
    assert_equal 2, Audit::Event.where(action: "post.published").count, "a duplicated id is acted on once"
    assert_predicate mine.reload, :live?
    assert_predicate theirs.reload, :live?
  end

  test "an author who may read but not publish gets the posts back as refused, one by one, each denial audited" do
    a = create_post(title: "A", published: false)
    b = create_post(title: "B", published: false)
    result = as(users(:author), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ a.id, b.id ]) }
    assert_empty result.done
    assert_equal [ a, b ].sort_by(&:id), result.refused.sort_by(&:id)
    assert_equal 0, result.not_found
    assert_nil a.reload.published_at
    assert_equal 2, Audit::Event.where(action: "access.denied").count
  end

  test "one refused post never blocks the others" do
    author = users(:author)
    mine = create_post(title: "Mine", published: false)
    mine.update_columns(author_id: author.id)
    other = create_post(title: "Other", published: false)
    group = AccessControl::Group.create!(name: "Own publishers")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: group, permission: "posts.publish", scope: { "own" => true })
    AccessControl::Membership.create!(group: group, user: author)

    result = as(author, channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ other.id, mine.id ]) }
    assert_equal [ mine ], result.done
    assert_equal [ other ], result.refused
    assert_predicate mine.reload, :live?
    assert_nil other.reload.published_at
  end

  test "a post outside the viewer's read scope is not found, never refused by name" do
    hidden = create_post(title: "Secret", content_type: "resume_entry")
    scoped = scoped_reader(content_types: %w[blog])
    result = as(scoped, channel: :admin) { Posts::Bulk.call(action: "trash", ids: [ hidden.id ]) }
    assert_equal 1, result.not_found
    assert_empty result.refused
    assert_empty result.done
    assert_not hidden.reload.trashed?
    assert_equal 0, Audit::Event.where(action: "access.denied").count
  end

  test "trash moves each post with its own event, a live one included" do
    a = create_post(title: "A")
    b = create_post(title: "B", published: true)
    as(users(:one), channel: :admin) do
      assert_equal 2, Posts::Bulk.call(action: "trash", ids: [ a.id, b.id ]).done.size
    end
    assert_equal 2, Audit::Event.where(action: "post.trashed").count
    assert_predicate a.reload, :trashed?
  end

  test "an already-live post is not counted as published, and no event is recorded for it" do
    live = create_post(title: "Live", published: true)
    draft = create_post(title: "Draft", published: false)
    before = Audit::Event.where(action: "post.published").count
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ live.id, draft.id ]) }
    assert_equal [ draft ], result.done
    assert_equal [ live ], result.already_live
    assert_equal 1, Audit::Event.where(action: "post.published").count - before
  end

  test "a scheduled post is skipped, never made live: its schedule is kept" do
    later = create_post(title: "Later", published: false)
    Posts::Save.call(later, attributes: { published_at: 3.days.from_now })
    scheduled_for = later.reload.published_at
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ later.id ]) }
    assert_empty result.done
    assert_equal [ later ], result.skipped_scheduled
    assert_equal scheduled_for, later.reload.published_at
    assert_equal "scheduled", later.status
  end

  test "a permission denial is refused; a validation failure is failed, with its reason" do
    ok = create_post(title: "Ok", published: false)
    broken = create_post(title: "Broken", published: false)
    broken.update_columns(content_type: "not_registered")
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ ok.id, broken.id ]) }
    assert_equal [ ok ], result.done
    assert_empty result.refused
    assert_equal [ broken ], result.failed
    assert_not_empty result.reasons.fetch(broken.id)

    denied = as(users(:author), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ broken.id ]) }
    assert_equal [ broken ], denied.refused
    assert_empty denied.failed
  end

  test "ids deduplicate as integers: 1, 01 and ' 1 ' name one post" do
    one = create_post(title: "One", published: false)
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ one.id.to_s, "0#{one.id}", " #{one.id} ", one.id ]) }
    assert_equal [ one ], result.done
    assert_equal 0, result.not_found
  end

  test "the read scope produces no duplicate rows for a content_types-scoped or own-scoped viewer" do
    a = create_post(title: "A", published: false)
    b = create_post(title: "B", published: false)
    scoped = scoped_reader(content_types: %w[blog])
    result = as(scoped, channel: :admin) { Posts::Bulk.call(action: "trash", ids: [ a.id, b.id ]) }
    assert_equal [ a, b ].sort_by(&:id), result.done.sort_by(&:id)
    assert_equal 2, Audit::Event.where(action: "post.trashed").count
  end

  test "a failure in one post rolls back only that one" do
    a = create_post(title: "A", published: false)
    b = create_post(title: "B", published: false)
    # Poison `a`'s save: a validation failure comes back as a failed result, and
    # `b` is still published.
    a.update_columns(content_type: "not_registered")
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ a.id, b.id ]) }
    assert_equal [ b ], result.done
    assert_equal [ a ], result.failed
    assert_predicate b.reload, :live?
    assert_nil a.reload.published_at
  end

  test "an unknown action and an oversized selection are programming errors" do
    assert_raises(ArgumentError) { Posts::Bulk.call(action: "delete", ids: [ 1 ]) }
    assert_raises(ArgumentError) { Posts::Bulk.call(action: "publish", ids: (1..201).to_a) }
    assert_nothing_raised { Posts::Bulk.call(action: "publish", ids: (1..200).to_a) }
  end

  test "junk ids are dropped as not found" do
    result = as(users(:one), channel: :admin) { Posts::Bulk.call(action: "publish", ids: [ "abc", "", nil, "99999999999999999999" ]) }
    assert_equal 3, result.not_found
  end
end
