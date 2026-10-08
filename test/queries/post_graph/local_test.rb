require "test_helper"

# `PostGraph::Local` (mind graph canvas spec §3.3): a post's or a tag's
# neighbourhood, one level per depth, over both kinds of connection.
class PostGraph::LocalTest < ActiveSupport::TestCase
  def local(focus, depth: 1, actor: nil, cap: PostGraph::CAP)
    PostGraph::Local.call(actor: actor, focus: focus, depth: depth, cap: cap, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })
  end

  def post_focus(post, actor: nil) = PostGraph::Focus.find(actor: actor, post: post.id)
  def tag_focus(name, actor: nil) = PostGraph::Focus.find(actor: actor, tag: Tag.find_by!(name: name).id)
  def relate(a, b) = PostRelation.create!(post: a, related_post: b)
  def ids(result) = result[:nodes].map { |n| n[:id] }.sort
  def tag_names(result) = result[:tags].map { |t| t[:name] }.sort

  setup do
    #   centre -- near -- far -- beyond
    #   centre, cousin share "shared"; far, cousin share "outer"; centre alone has "solo"
    @centre = create_post(title: "Centre", tags: %w[shared solo])
    @near = create_post(title: "Near")
    @far = create_post(title: "Far", tags: %w[outer])
    @beyond = create_post(title: "Beyond")
    @cousin = create_post(title: "Cousin", tags: %w[shared outer])
    relate(@centre, @near)
    relate(@far, @near) # stored the other way round on purpose: relations read as undirected
    relate(@far, @beyond)
  end

  test "depth 1 from a post: its related posts and its shared tags, not the tags' other posts" do
    result = local(post_focus(@centre))

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_equal %w[shared], tag_names(result), "a tag on one readable post is no node"
    assert_equal({ kind: "post", id: @centre.id, node_id: @centre.id, title: "Centre", depth: 1 }, result[:focus])
    assert_equal 2, result[:tags].first[:count], "the readable count, not the one drawn post"
    assert_equal 1, result[:tags].first[:degree]
  end

  test "depth 2 from a post adds the neighbours' neighbours and the tags' other posts" do
    result = local(post_focus(@centre), depth: 2)

    assert_equal [ @centre.id, @near.id, @far.id, @cousin.id ].sort, ids(result)
    assert_not_includes ids(result), @beyond.id
    assert_includes tag_names(result), "shared"
    assert_equal 2, result[:focus][:depth]
  end

  test "depth 1 from a tag: the posts that carry it; depth 2: their related posts and other tags" do
    one = local(tag_focus("shared"))
    two = local(tag_focus("shared"), depth: 2)

    assert_equal [ @centre.id, @cousin.id ].sort, ids(one)
    assert_equal %w[shared], tag_names(one)
    assert_equal [ @centre.id, @cousin.id, @near.id ].sort, ids(two)
    assert_equal %w[outer shared], tag_names(two)
    assert_equal "tag-#{Tag.find_by!(name: "shared").id}", two[:focus][:node_id]
  end

  test "a focused tag is a node even with one readable post" do
    result = local(tag_focus("solo"))

    assert_equal [ @centre.id ], ids(result)
    assert_equal %w[solo], tag_names(result)
    assert_equal 1, result[:tags].first[:count]
  end

  test "a depth other than 2 is 1" do
    assert_equal 1, local(post_focus(@centre), depth: 7)[:focus][:depth]
    assert_equal 1, local(post_focus(@centre), depth: "x")[:focus][:depth]
    assert_equal 2, local(post_focus(@centre), depth: "2")[:focus][:depth]
  end

  test "every edge is between two drawn nodes, and degrees count them" do
    result = local(post_focus(@centre), depth: 2)
    node_ids = ids(result) + result[:tags].map { |t| t[:id] }

    assert result[:edges].all? { |edge| node_ids.include?(edge[:source]) && node_ids.include?(edge[:target]) }
    centre = result[:nodes].find { |n| n[:id] == @centre.id }
    assert_equal result[:edges].count { |edge| edge[:source] == @centre.id || edge[:target] == @centre.id }, centre[:degree]
  end

  test "over the cap the focus stays, nearer posts come first, and total says how many there were" do
    result = local(post_focus(@centre), depth: 2, cap: 2)

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_equal 4, result[:total]
    assert_equal 2, result[:shown]
  end

  test "an unreadable or trashed neighbour is no node, no edge, and not in a tag's count" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    [ @centre, @near ].each { |post| post.update_column(:author_id, users(:author).id) }

    result = as(users(:author)) { local(post_focus(@centre, actor: users(:author)), depth: 2, actor: users(:author)) }

    assert_equal [ @centre.id, @near.id ].sort, ids(result)
    assert_empty result[:tags], "'shared' has one readable post for this viewer"

    @near.update_column(:trashed_at, Time.current)
    assert_equal [ @centre.id ], ids(local(post_focus(@centre)))
  end

  test "the number of statements depends on the depth, not on the neighbourhood's size" do
    few = capture_sql { local(post_focus(@centre), depth: 2) }.size
    6.times { |i| relate(@centre, create_post(title: "More #{i}", tags: %w[shared])) }
    many = capture_sql { local(post_focus(@centre), depth: 2) }.size

    assert_equal few, many
  end
end
