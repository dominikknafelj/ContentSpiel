require "test_helper"

class PublicBlocksTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(tagline: "Writing about Rails")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "the homepage shows the tagline eyebrow and rich text in prose" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: "<p>Hello there</p>")
    get "/"

    assert_includes response.body, "Writing about Rails"
    assert_select ".cs-prose", text: /Hello there/
  end

  test "an image block renders its alt text and caption" do
    block = @root.content_blocks.create!(block_type: :image, position: 0, caption: "Our studio", alt: "A bright room")
    block.image.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "icon.png")
    get "/"

    assert_select "img[alt='A bright room']"
    assert_select "figcaption", text: /Our studio/
  end

  test "blog rows show date, excerpt and first tag" do
    post = Post.create!(content_type: :blog, title: "Notes on Hotwire", excerpt: "What stayed simple",
      published_at: Time.zone.local(2026, 9, 12))
    post.tags << Tag.create!(name: "rails")
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    get "/"

    assert_includes response.body, "12 Sep 2026"
    assert_includes response.body, "What stayed simple"
    assert_select "li", text: /rails/
  end

  test "resume rows show company, role type and period" do
    Post.create!(content_type: :resume_entry, title: "Staff Engineer", company: "Acme", role_type: "lead",
      start_date: "2023-01-01", end_date: "", published_at: 1.day.ago)
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    get "/"

    assert_includes response.body, "Acme"
    assert_includes response.body, "Lead"
    assert_includes response.body, "2023 – now"
  end

  test "a now list shows the latest update's text" do
    Post.create!(content_type: :now_update, title: "Now", body: "<p>Training for a half marathon</p>", published_at: 1.day.ago)
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })
    get "/"

    assert_includes response.body, "Training for a half marathon"
  end

  test "a post detail shows date, excerpt and tags" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title: "Hello", excerpt: "Short summary",
      published_at: Time.zone.local(2026, 9, 12), body: "<p>Body text</p>")
    post.tags << Tag.create!(name: "hotwire")
    get "/blog/hello"

    assert_includes response.body, "12 Sep 2026"
    assert_includes response.body, "Short summary"
    assert_includes response.body, "hotwire"
    assert_select "article .cs-prose", text: /Body text/
  end
end
