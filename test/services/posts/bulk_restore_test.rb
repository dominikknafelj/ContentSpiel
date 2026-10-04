require "test_helper"

class Posts::BulkRestoreTest < ActiveSupport::TestCase
  def trashed_post(title)
    post = create_post(title: title, published: false)
    as(users(:one), channel: :admin) { Trash::Move.call(post) }
    post
  end

  test "restores each trashed post once and counts everything else as not found" do
    a = trashed_post("A")
    b = trashed_post("B")
    kept = create_post(title: "Kept")
    result = as(users(:one), channel: :admin) { Posts::BulkRestore.call(ids: [ a.id, b.id, a.id.to_s, kept.id, 999_999, "abc" ]) }
    assert_equal [ a, b ].sort_by(&:id), result.restored.sort_by(&:id)
    assert_equal 3, result.not_found
    assert_equal 2, Audit::Event.where(action: "post.restored").count
    assert_not a.reload.trashed?
  end

  test "a post outside the delete scope is not found; one the actor may not restore is never named" do
    hidden = create_post(title: "Secret", content_type: "resume_entry", published: false)
    as(users(:one), channel: :admin) { Trash::Move.call(hidden) }
    scoped = User.create!(email_address: "restorer@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Blog restorers")
    %w[posts.read posts.delete].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: { "content_types" => %w[blog] }) }
    AccessControl::Membership.create!(group: group, user: scoped)
    result = as(scoped, channel: :admin) { Posts::BulkRestore.call(ids: [ hidden.id ]) }
    assert_equal 1, result.not_found
    assert_empty result.restored + result.refused + result.failed
    assert_predicate hidden.reload, :trashed?
  end

  test "one failing restore is failed, with its reason, and the others still come back" do
    a = trashed_post("A")
    b = trashed_post("B")
    a.update_columns(content_type: "not_registered")
    result = as(users(:one), channel: :admin) { Posts::BulkRestore.call(ids: [ a.id, b.id ]) }
    assert_equal [ b ], result.restored
    assert_equal [ a ], result.failed
    assert_not_empty result.reasons.fetch(a.id)
    assert_predicate a.reload, :trashed?
  end

  test "more than the maximum is an ArgumentError" do
    assert_raises(ArgumentError) { Posts::BulkRestore.call(ids: (1..201).to_a) }
  end
end
