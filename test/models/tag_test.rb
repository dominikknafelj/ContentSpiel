require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "name is required" do
    tag = Tag.new
    assert_not tag.valid?
  end

  test "name must be unique" do
    Tag.create!(name: "rails")
    duplicate = Tag.new(name: "rails")

    assert_not duplicate.valid?
  end

  test "a post can have many tags and a tag can belong to many posts" do
    post = Post.create!(content_type: :blog, title: "Hello")
    tag = Tag.create!(name: "rails")

    post.tags << tag

    assert_includes post.tags, tag
    assert_includes tag.posts, post
  end
end
