require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "title is required" do
    post = Post.new(content_type: :blog)
    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "slug is auto-generated from title when blank" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal "hello-world", post.slug
  end

  test "slug must be unique within the same content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    duplicate = Post.new(content_type: :blog, title: "Hello World")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "the same slug is allowed across different content_types" do
    Post.create!(content_type: :blog, title: "Hello World")
    other = Post.new(content_type: :resume_entry, title: "Hello World")

    assert other.valid?
  end

  test "metadata defaults to an empty hash" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal({}, post.metadata)
  end

  test "body accepts rich text content" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")
    assert post.body.present?
    assert_includes post.body.to_plain_text, "Hi"
  end
end
