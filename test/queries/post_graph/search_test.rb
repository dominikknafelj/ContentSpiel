require "test_helper"

class PostGraph::SearchTest < ActiveSupport::TestCase
  def search(text, actor: nil, limit: 10) = PostGraph::Search.call(actor: actor, text: text, limit: limit)

  test "posts by title and tags by name, posts first" do
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Unrelated")
    tag = Tag.find_by!(name: "ruby")

    assert_equal [ { kind: "post", id: post.id, label: "Ruby notes" }, { kind: "tag", id: tag.id, label: "ruby" } ], search("rub")
  end

  test "a typed % or _ is a character, not a wildcard" do
    create_post(title: "Plain")

    assert_empty search("%")
    assert_empty search("_")
  end

  test "an unreadable or trashed post is not listed, nor a tag only such posts carry" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Secret plan", tags: [ "secret" ])
    gone = create_post(title: "Secret bin", tags: [ "secretbin" ])
    gone.update_column(:trashed_at, Time.current)

    assert_empty as(users(:author)) { search("secret", actor: users(:author)) }
    assert_equal [ "Secret plan", "secret" ], search("secret").map { |row| row[:label] }
  end

  test "at most `limit` of each" do
    3.times { |i| create_post(title: "Many #{i}", tags: [ "many#{i}" ]) }

    rows = search("many", limit: 2)

    assert_equal 2, rows.count { |row| row[:kind] == "post" }
    assert_equal 2, rows.count { |row| row[:kind] == "tag" }
  end

  test "blank text finds nothing" do
    create_post(title: "A")

    assert_empty search("  ")
  end
end
