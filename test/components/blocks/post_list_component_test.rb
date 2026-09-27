require "test_helper"

class Blocks::PostListComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "a blog list renders titles linked to their canonical URLs" do
    page = root_page
    block = page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "Notes on Hotwire")

    render_inline(Blocks::PostListComponent.new(block: block, page: page))

    assert_selector "a[href='#{PublicSite::Urls.new.path_for(post)}']", text: "Notes on Hotwire"
  end

  test "limit trims the list" do
    page = root_page
    block = page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog", "limit" => 1 })
    create_post(title: "First", published: true)
    create_post(title: "Second", published: true)

    render_inline(Blocks::PostListComponent.new(block: block, page: page))

    assert_selector "li", count: 1
  end

  test "an unfiltered post list renders every type with the default rows" do
    page = root_page
    block = page.content_blocks.create!(block_type: :post_list, position: 0, settings: {})
    create_post(title: "A blog post", content_type: "blog")
    create_post(title: "A resume entry", content_type: "resume_entry")

    render_inline(Blocks::PostListComponent.new(block: block, page: page))

    # The default type's list component (blog) renders every post
    # regardless of its own content type -- a blank `content_type` in
    # `settings` means "every type", so there is no single type left to pick
    # a *different* list component from.
    assert_text "A blog post"
    assert_text "A resume entry"
    assert_selector "ul li", count: 2
  end
end
