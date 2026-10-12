require "test_helper"

class Posts::ResumeListComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "the period, company and role-type label render" do
    page = root_page
    # A post_list block naming this content type, created before the post is
    # saved, is what gives the post a canonical page at all -- without one,
    # `PublicSite::Paths.canonical_page` finds nothing to resolve
    # `post_url_path` against, and `link_to(title, nil)` raises rather than
    # rendering a blank href.
    page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    publish_changes(page)
    post = Post.new(content_type: "resume_entry", title: "Staff Engineer", published_at: 1.day.ago)
    post.assign_fields({ "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" }, locale: "en")
    post.save!

    render_inline(Posts::ResumeListComponent.new(posts: [ post ], page: page))

    assert_text "2023 – now"
    assert_text "Acme"
    assert_text "Lead"
  end
end
