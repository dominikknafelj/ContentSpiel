require "test_helper"

# `BlockTypes::PostList`'s criteria by themselves: what a list block with
# these settings lists, asked for a type and tag names with no record.
class BlockTypes::PostListTest < ActiveSupport::TestCase
  Criteria = Struct.new(:content_type, :tag)

  test "matches? is the listing's criteria for a type and tag names, with no record" do
    assert BlockTypes::PostList.matches?(Criteria.new(nil, nil), content_type: "blog", tag_names: [])
    assert BlockTypes::PostList.matches?(Criteria.new("blog", " Rails "), content_type: "blog", tag_names: %w[rails other])
    assert_not BlockTypes::PostList.matches?(Criteria.new("blog", nil), content_type: "resume_entry", tag_names: [])
    assert_not BlockTypes::PostList.matches?(Criteria.new(nil, "rails"), content_type: "blog", tag_names: %w[ruby])
    assert_not BlockTypes::PostList.matches?(Criteria.new(nil, nil), content_type: "gone/thing", tag_names: []), "a post of a type that is not registered is listed nowhere"
  end

  test "lists? and matches? are one answer" do
    post = create_post(title: "A", tags: [ "Rails" ])
    [ Criteria.new(nil, nil), Criteria.new("blog", "rails"), Criteria.new("resume_entry", nil), Criteria.new(nil, "ruby") ].each do |criteria|
      assert_equal BlockTypes::PostList.lists?(criteria, post),
        BlockTypes::PostList.matches?(criteria, content_type: post.content_type, tag_names: post.tags.map(&:name)), criteria.to_a.inspect
    end
  end
end
