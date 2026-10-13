require "test_helper"

class PostGraph::FocusTest < ActiveSupport::TestCase
  test "neither id: no focus" do
    assert_nil PostGraph::Focus.find(actor: nil)
    assert_nil PostGraph::Focus.find(actor: nil, post: "", tag: " ")
  end

  test "a readable post is a focus with its title" do
    post = create_post(title: "Alpha")

    focus = PostGraph::Focus.find(actor: nil, post: post.id.to_s)

    assert_equal [ "post", post.id, "Alpha", "post-#{post.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
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

  # An id is decimal digits and nothing else. Ruby's `Integer("010")` is 8 and
  # `Integer("0x1A")` 26: either would open a post other than the one the URL
  # names.
  test "an id is read as a decimal: a leading zero is not octal, and a prefixed form names nothing" do
    # Ten of them, so the last one's id has two digits at least, whatever the
    # sequence started at: "07" is 7 either way.
    post = 10.times.map { |i| create_post(title: "Post #{i}", tags: [ "t#{i}" ]) }.last
    tag = Tag.find_by!(name: "t9")
    assert_operator tag.id, :>=, 10

    assert_equal post.id, PostGraph::Focus.find(actor: nil, post: "0#{post.id}").id
    assert_equal post.id, PostGraph::Focus.find(actor: nil, post: "00#{post.id}").id
    assert_equal tag.id, PostGraph::Focus.find(actor: nil, tag: "0#{tag.id}").id
    [ "0x#{post.id.to_s(16)}", "0b#{post.id.to_s(2)}", "0o#{post.id.to_s(8)}", "#{post.id}.0", "#{post.id}abc", [ post.id.to_s ], { "id" => post.id.to_s } ].each do |value|
      assert_raises(ActiveRecord::RecordNotFound, "post=#{value.inspect} was found") { PostGraph::Focus.find(actor: nil, post: value) }
    end
    [ "0x#{tag.id.to_s(16)}", [ tag.id.to_s ] ].each do |value|
      assert_raises(ActiveRecord::RecordNotFound, "tag=#{value.inspect} was found") { PostGraph::Focus.find(actor: nil, tag: value) }
    end
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

  test "a readable page is a focus with its title" do
    page = create_page(title: "About")

    focus = PostGraph::Focus.find(actor: nil, page: page.id.to_s)

    assert_equal [ "page", page.id, "About", "page-#{page.id}" ], [ focus.kind, focus.id, focus.title, focus.node_id ]
  end

  test "page wins over post, and post over tag" do
    page = create_page(title: "About")
    post = create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    assert_equal "page", PostGraph::Focus.find(actor: nil, page: page.id, post: post.id, tag: tag.id).kind
    assert_equal "post", PostGraph::Focus.find(actor: nil, post: post.id, tag: tag.id).kind
  end

  test "a page focus that is a list, hexadecimal, trashed or out of scope is not found, and 010 is page 10" do
    page = create_page(title: "About")
    hidden = create_page(title: "Hidden")
    gone = create_page(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ page.id ] })

    [ [ "1" ], "0x1A", "about", "-#{page.id}", "0", gone.id, Page.maximum(:id) + 1 ].each do |value|
      assert_raises(ActiveRecord::RecordNotFound, value.inspect) { PostGraph::Focus.find(actor: nil, page: value) }
    end
    assert_raises(ActiveRecord::RecordNotFound) { as(users(:author)) { PostGraph::Focus.find(actor: users(:author), page: hidden.id) } }
    assert_equal page.id, PostGraph::Focus.find(actor: nil, page: "0#{page.id}").id
  end

  test "a tag only a readable page lists is a focus, and one only an unreadable page lists is not" do
    seen = create_page(title: "Seen")
    hidden = create_page(title: "Hidden")
    ContentBlock.create!(owner: seen, block_type: :post_list, position: 0, settings: { "tag" => " Listed " })
    ContentBlock.create!(owner: hidden, block_type: :post_list, position: 0, settings: { "tag" => "secret" })
    listed = Tag.create!(name: "listed")
    secret = Tag.create!(name: "secret")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    assert_equal "tag", PostGraph::Focus.find(actor: nil, tag: listed.id).kind
    as(users(:author)) do
      assert_equal "tag", PostGraph::Focus.find(actor: users(:author), tag: listed.id).kind
      assert_raises(ActiveRecord::RecordNotFound) { PostGraph::Focus.find(actor: users(:author), tag: secret.id) }
    end
  end
end
