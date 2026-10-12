require "test_helper"

class Posts::BlogListComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "shows date, excerpt and first tag" do
    page = root_page
    page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    publish_changes(page)
    post = Post.create!(content_type: :blog, title: "Notes on Hotwire", excerpt: "What stayed simple",
      published_at: Time.zone.local(2026, 9, 12))
    post.tags << Tag.create!(name: "rails")

    render_inline(Posts::BlogListComponent.new(posts: Post.where(id: post.id).includes(:tags), page: page))

    assert_text "12 Sep 2026"
    assert_text "What stayed simple"
    assert_selector "li", text: /rails/
  end
end
