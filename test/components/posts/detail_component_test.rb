require "test_helper"

class Posts::DetailComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "shows date, excerpt and tags" do
    post = Post.create!(content_type: :blog, title: "Hello", excerpt: "Short summary",
      published_at: Time.zone.local(2026, 9, 12), body: rich_doc("Body text"))
    post.tags << Tag.create!(name: "hotwire")

    render_inline(Posts::DetailComponent.new(post: post))

    assert_text "12 Sep 2026"
    assert_text "Short summary"
    assert_text "hotwire"
    assert_selector "article .cs-prose", text: "Body text"
  end
end
