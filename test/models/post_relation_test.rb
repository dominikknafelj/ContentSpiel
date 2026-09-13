require "test_helper"

class PostRelationTest < ActiveSupport::TestCase
  setup do
    @post_a = Post.create!(content_type: :blog, title: "Post A")
    @post_b = Post.create!(content_type: :blog, title: "Post B")
  end

  test "a post can relate to another post" do
    relation = PostRelation.create!(post: @post_a, related_post: @post_b)
    assert relation.persisted?
  end

  test "a post cannot relate to itself" do
    relation = PostRelation.new(post: @post_a, related_post: @post_a)
    assert_not relation.valid?
  end

  test "the reverse pair is rejected once a relation exists" do
    PostRelation.create!(post: @post_a, related_post: @post_b)
    reverse = PostRelation.new(post: @post_b, related_post: @post_a)

    assert_not reverse.valid?
    assert_includes reverse.errors[:base], "relation already exists in the opposite direction"
  end

  test "destroying the post on the forward side removes the relation" do
    PostRelation.create!(post: @post_a, related_post: @post_b)

    assert_difference -> { PostRelation.count }, -1 do
      @post_a.destroy!
    end
  end

  # A PostRelation has two FKs into posts. Without the inverse association the
  # `related_post_id` side is left dangling and destroy raises InvalidForeignKey.
  test "destroying the post on the related_post side removes the relation" do
    relation = PostRelation.create!(post: @post_a, related_post: @post_b)

    assert_difference -> { PostRelation.count }, -1 do
      @post_b.destroy!
    end

    assert_not PostRelation.exists?(relation.id)
  end

  test "all_related_posts returns posts related in either direction" do
    PostRelation.create!(post: @post_a, related_post: @post_b)

    assert_equal [ @post_b ], @post_a.all_related_posts.to_a
    assert_equal [ @post_a ], @post_b.all_related_posts.to_a
  end
end
