require "test_helper"

class PostGraph::FocusTest < ActiveSupport::TestCase
  test "neither id: no focus" do
    assert_nil PostGraph::Focus.find(actor: nil)
    assert_nil PostGraph::Focus.find(actor: nil, post: "", tag: " ")
  end

  test "a readable post is a focus with its title" do
    post = create_post(title: "Alpha")

    focus = PostGraph::Focus.find(actor: nil, post: post.id.to_s)

    assert_equal [ "post", post.id, "Alpha", post.id ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "a tag a readable post carries is a focus with its name" do
    create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    focus = PostGraph::Focus.find(actor: nil, tag: tag.id)

    assert_equal [ "tag", tag.id, "ruby", "tag-#{tag.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "post wins when both are given" do
    post = create_post(title: "A", tags: [ "ruby" ])

    assert_equal "post", PostGraph::Focus.find(actor: nil, post: post.id, tag: Tag.find_by!(name: "ruby").id).kind
  end

  test "an unknown, trashed or unreadable post is not found" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    other = create_post(title: "Other")
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current)

    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: 0) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: "abc") }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, post: gone.id) }
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), post: other.id) } }
  end

  test "an unknown tag, and a tag only unreadable or trashed posts carry, is not found" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Other", tags: [ "theirs" ])
    gone = create_post(title: "Gone", tags: [ "binned" ])
    gone.update_column(:trashed_at, Time.current)
    unused = Tag.create!(name: "unused")

    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: 0) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: unused.id) }
    assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: nil, tag: Tag.find_by!(name: "binned").id) }
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), tag: Tag.find_by!(name: "theirs").id) } }
  end
end
