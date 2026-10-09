require "test_helper"

class PublicBlocksTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(tagline: "Writing about Rails")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "the homepage shows the tagline eyebrow and rich text in prose" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello there"))
    get "/"

    assert_includes response.body, "Writing about Rails"
    assert_select ".cs-prose", text: /Hello there/
  end

  test "an image block renders its alt text and caption" do
    @root.content_blocks.create!(block_type: :image, position: 0, caption: "Our studio", alt: "A bright room", media_asset: create_media_asset)
    get "/"

    assert_select "img[alt='A bright room']"
    assert_select "figcaption", text: /Our studio/
  end

  # Task 4 review, addressed in Task 5: an image block's own `media_asset`
  # was one query per block (`Blocks::ImageComponent#asset` ->
  # `block.media_asset`) until `PublicPageRendering#preload_page_images`
  # started preloading every block's asset (and the page's hero) in one
  # batch before the page ever renders. The `media_assets` query count for
  # a page render must not grow with how many image blocks it has.
  test "a page with more image blocks doesn't query media_assets once per block" do
    @root.content_blocks.create!(block_type: :image, position: 0, media_asset: create_media_asset)

    one_block_queries = 0
    ActiveSupport::Notifications.subscribed(lambda { |name, started, finished, unique_id, payload|
      one_block_queries += 1 if payload[:sql].include?("media_assets")
    }, "sql.active_record") { get "/" }

    4.times { |i| @root.content_blocks.create!(block_type: :image, position: i + 1, media_asset: create_media_asset) }

    five_block_queries = 0
    ActiveSupport::Notifications.subscribed(lambda { |name, started, finished, unique_id, payload|
      five_block_queries += 1 if payload[:sql].include?("media_assets")
    }, "sql.active_record") { get "/" }

    assert_equal one_block_queries, five_block_queries,
      "Adding more image blocks should not increase media_assets query count (N+1 issue). " \
      "1 block: #{one_block_queries} queries, 5 blocks: #{five_block_queries} queries"
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

  test "blog post listing does not N+1 on tags" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

    # Create 2 tagged posts and count queries
    2.times do |i|
      post = Post.create!(content_type: :blog, title: "Post #{i}", published_at: Time.current - i.days)
      post.tags << Tag.create!(name: "tag#{i}")
    end

    tag_queries_2_posts = 0
    ActiveSupport::Notifications.subscribed(lambda { |name, started, finished, unique_id, payload|
      tag_queries_2_posts += 1 if payload[:sql].include?("tags")
    }, "sql.active_record") do
      get "/"
    end

    # Create 2 more tagged posts (4 total)
    2.times do |i|
      post = Post.create!(content_type: :blog, title: "Post #{i+2}", published_at: Time.current - (i+2).days)
      post.tags << Tag.create!(name: "tag#{i+2}")
    end

    tag_queries_4_posts = 0
    ActiveSupport::Notifications.subscribed(lambda { |name, started, finished, unique_id, payload|
      tag_queries_4_posts += 1 if payload[:sql].include?("tags")
    }, "sql.active_record") do
      get "/"
    end

    # Query count should be the same regardless of post count (with includes, we get
    # one query for posts + one for all tags, not one per post)
    assert_equal tag_queries_2_posts, tag_queries_4_posts,
      "Adding more posts should not increase tag query count (N+1 issue). 2 posts: #{tag_queries_2_posts} queries, 4 posts: #{tag_queries_4_posts} queries"
  end

  test "resume rows show company, role type and period" do
    post = Post.new(content_type: "resume_entry", title: "Staff Engineer", published_at: 1.day.ago)
    post.assign_fields({ "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" }, locale: "en")
    post.save!
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    get "/"

    assert_includes response.body, "Acme"
    assert_includes response.body, "Lead"
    assert_includes response.body, "2023 – now"
  end

  test "a now list shows the latest update's text" do
    Post.create!(content_type: :now_update, title: "Now", body: rich_doc("Training for a half marathon"), published_at: 1.day.ago)
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })
    get "/"

    assert_includes response.body, "Training for a half marathon"
  end

  test "an unregistered stored block type is skipped on render" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello there"))
    gallery = @root.content_blocks.create!(block_type: :rich_text, position: 1, body: rich_doc("Gone"))
    gallery.update_column(:block_type, "gallery")

    get "/"

    assert_response :success
    assert_select ".cs-prose", text: /Hello there/
    assert_not_includes response.body, "Gone"
  end

  test "a post detail shows date, excerpt and tags" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title: "Hello", excerpt: "Short summary",
      published_at: Time.zone.local(2026, 9, 12), body: rich_doc("Body text"))
    post.tags << Tag.create!(name: "hotwire")
    get "/blog/hello"

    assert_includes response.body, "12 Sep 2026"
    assert_includes response.body, "Short summary"
    assert_includes response.body, "hotwire"
    assert_select "article .cs-prose", text: /Body text/
  end

  def section_with_texts(*columns, layout: "two")
    section = @root.content_blocks.create!(block_type: :section, position: 5, settings: { "layout" => layout })
    columns.each_with_index do |(column, text), index|
      @root.content_blocks.create!(block_type: :rich_text, section: section, section_column: column, position: index, body: rich_doc(text))
    end
    section
  end

  test "a section renders its blocks once, inside it, column by column" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Before the band"))
    section_with_texts([ 2, "Right text" ], [ 1, "Left text" ])
    get "/"

    assert_select "section.content-section", 1
    assert_select "section.content-section .content-section__column", 2
    assert_select ".cs-prose", 3
    assert_operator response.body.index("Before the band"), :<, response.body.index("Left text")
    assert_operator response.body.index("Left text"), :<, response.body.index("Right text")
  end

  test "a post's permalink shows the post in place of its listing when the listing sits in a column" do
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: @root, published_at: Time.current)
    section = blog.content_blocks.create!(block_type: :section, position: 0)
    blog.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0, body: rich_doc("Beside the list"))
    blog.content_blocks.create!(block_type: :post_list, section: section, section_column: 2, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "In a column")
    other = create_post(title: "Another post")
    PublicSite::Paths.sync_posts("blog")

    get "/blog/#{post.slug}"

    assert_response :success
    assert_select "h1", text: "In a column"
    assert_includes response.body, "Beside the list"
    assert_not_includes response.body, other.title
  end
end
