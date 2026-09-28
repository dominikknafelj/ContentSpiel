require "test_helper"

class Posts::NowListComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "shows the latest update's text" do
    page = root_page
    post = Post.create!(content_type: :now_update, title: "Now", body_doc: rich_doc("Training for a half marathon"), published_at: 1.day.ago)

    render_inline(Posts::NowListComponent.new(posts: [ post ], page: page))

    assert_text "Training for a half marathon"
  end

  test "renders nothing for an empty list" do
    page = root_page

    render_inline(Posts::NowListComponent.new(posts: Post.none, page: page))

    assert_no_text "Now"
  end
end
