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

  # The same for a page served from its COPY: its blocks are rebuilt objects
  # set as a loaded association, and `preload_page_images` preloads their
  # images in one batch all the same.
  test "a page served from its copy with more image blocks doesn't use more statements" do
    page = create_page(title: "Gallery")
    add_image = lambda do
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: create_media_asset.id })
      assert result.ok?, result.errors.to_sentence
    end
    path = PublicSite::Urls.new.path_for(page, :en)
    add_image.call
    publish_changes(page)
    get path # warms what the first request of a process loads once
    one_block = capture_sql { get path }
    assert copied?(page)

    4.times { add_image.call }
    publish_changes(page)
    five_blocks = capture_sql { get path }

    assert_equal 5, controller.instance_variable_get(:@page).content_blocks.size
    assert_equal one_block.size, five_blocks.size, "1 block: #{one_block.size} statements, 5 blocks: #{five_blocks.size}"
    assert_equal one_block.count { |sql| sql.include?("media_assets") }, five_blocks.count { |sql| sql.include?("media_assets") }
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

  # A section goes after the blocks in it: the database keeps a section that
  # still holds one (`content_blocks.section_id`).
  def clear_blocks
    @root.content_blocks.where.not(section_id: nil).destroy_all
    @root.content_blocks.reload.destroy_all
  end

  # An image with its variants made, so its `<img>` carries `srcset` and
  # `sizes` (`Media::PictureComponent` writes neither for an unprocessed
  # one). The pattern is `test/components/media/picture_component_test.rb`'s.
  def processed_asset
    asset = create_media_asset(filename: "wide.png")
    asset.file.analyze
    asset.update_columns(asset.file.blob.metadata.slice("width", "height"))
    perform_enqueued_jobs
    asset
  end

  def section_with_texts(*columns, layout: "two", background: "none", width: "content")
    section = @root.content_blocks.create!(block_type: :section, position: 5,
      settings: { "layout" => layout, "background" => background, "width" => width })
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
    PublicSite::Paths.refresh(posts: Post.where(content_type: "blog"))

    get "/blog/#{post.slug}"

    assert_response :success
    assert_select "h1", text: "In a column"
    assert_includes response.body, "Beside the list"
    assert_not_includes response.body, other.title
    # In the listing's own column, not merely somewhere on the page: the swap
    # is `render_block`'s, wherever the block sits.
    assert_select "section.content-section .content-section__column:nth-child(1) .cs-prose", text: /Beside the list/
    assert_select "section.content-section .content-section__column:nth-child(2) h1", text: "In a column"
    assert_select "h1", 1
  end

  # Which of two listings that both list the post its detail stands in for is
  # the FIRST IN READING ORDER (`BlockOutline#reading_order`), never the one
  # with the lowest `position`: a position is counted per container, so the
  # listing in a column of the page's first section (position 5 in its
  # column) is read before the top-level listing under it (position 1), and
  # two of them can tie. Asked three times: an order the database happens to
  # return must not decide it.
  test "a post's permalink stands in for the first listing in reading order, in a column or not, on every request" do
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: @root, published_at: Time.current)
    section = blog.content_blocks.create!(block_type: :section, position: 0)
    blog.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 4, body: rich_doc("Before the first listing"))
    in_column = blog.content_blocks.create!(block_type: :post_list, section: section, section_column: 1, position: 5, settings: { "content_type" => "blog" })
    top_level = blog.content_blocks.create!(block_type: :post_list, position: 1, settings: { "content_type" => "blog" })
    assert_operator top_level.position, :<, in_column.position
    post = create_post(title: "Listed twice")
    other = create_post(title: "Another post")
    PublicSite::Paths.refresh(posts: Post.where(content_type: "blog"))

    3.times do
      get "/blog/#{post.slug}"

      assert_response :success
      assert_select "h1", 1
      assert_select "section.content-section .content-section__column:nth-child(1) h1", text: "Listed twice"
      # The second listing is still a listing, under the section, with both posts.
      assert_select "section.content-section a", text: other.title, count: 0
      assert_includes response.body, other.title
      assert_operator response.body.index("Before the first listing"), :<, response.body.index("<h1")
      assert_operator response.body.index("<h1"), :<, response.body.rindex(other.title)
    end
  end

  # The controller reads the reading order from an outline, and the view
  # draws from the same one (`PublicPageRendering#assign_record` hands it
  # over): a permalink builds one outline, as a page does.
  test "a post's permalink builds one outline, the one its page is drawn from" do
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: @root, published_at: Time.current)
    section = blog.content_blocks.create!(block_type: :section, position: 0)
    blog.content_blocks.create!(block_type: :post_list, section: section, section_column: 1, position: 0, settings: { "content_type" => "blog" })
    post = create_post(title: "Counted")
    PublicSite::Paths.refresh(posts: Post.where(content_type: "blog"))
    built = 0
    original = BlockOutline.method(:new)

    with_singleton_override(BlockOutline, :new, ->(*arguments) { built += 1; original.call(*arguments) }) { get "/blog/#{post.slug}" }

    assert_select "section.content-section h1", text: "Counted"
    assert_equal 1, built
  end

  test "each layout renders its own grid class and one column element per column, an empty one kept" do
    { "one" => 1, "two" => 2, "three" => 3, "four" => 4, "one_two" => 2, "two_one" => 2 }.each do |layout, count|
      clear_blocks
      section_with_texts([ 1, "Only the first column" ], layout: layout)
      get "/"

      assert_select "section.content-section > .content-section__inner > .content-section__grid.content-section__grid--#{layout}", 1
      assert_select "section.content-section .content-section__grid > .content-section__column", count
      assert_select "section.content-section .content-section__column:first-child .cs-prose", 1
      # Empty for CSS too (`:empty`, which whitespace would defeat): a
      # stacked section hides an empty column instead of leaving its gap.
      css_select("section.content-section .content-section__column").drop(1).each { |column| assert_empty column.children }
    end
  end

  test "a section is a plain grouping element: no heading of its own, no label, no landmark role" do
    section_with_texts([ 1, "Text" ])
    get "/"

    assert_select "section.content-section[aria-label], section.content-section[aria-labelledby], section.content-section[role]", 0
    assert_select "section.content-section > h1, section.content-section > h2", 0
  end

  test "background and width are classes, and the default is neither band nor full" do
    section_with_texts([ 1, "Plain" ])
    section_with_texts([ 1, "Band" ], background: "strong", width: "full")
    get "/"

    assert_select "section.content-section.content-section--none.content-section--content", 1
    assert_select "section.content-section.content-section--strong.content-section--full", 1
  end

  test "settings this code doesn't know read as the defaults and never reach the class list" do
    section = section_with_texts([ 1, "Text" ])
    section.update_columns(settings: { "layout" => "nine", "background" => "x onload", "width" => "huge" })
    get "/"

    assert_select "section[class='content-section content-section--none content-section--content']", 1
    assert_select ".content-section__grid[class='content-section__grid content-section__grid--two']", 1
    assert_select ".content-section__column", 2
  end

  test "a section with no blocks renders nothing" do
    @root.content_blocks.create!(block_type: :section, position: 0)
    get "/"

    assert_select "section.content-section", 0
  end

  # The rule for a top-level block of an unregistered type, kept in a column:
  # skipped, and the section around it drawn. A section holding nothing that
  # can be drawn is an empty one.
  test "a block of an unregistered type in a column is skipped, and a section of nothing else renders nothing" do
    section = section_with_texts([ 1, "Still here" ], [ 2, "Gone" ])
    @root.content_blocks.find_by!(section: section, section_column: 2).update_column(:block_type, "gallery")
    get "/"

    assert_response :success
    assert_select "section.content-section .content-section__column", 2
    assert_select "section.content-section .cs-prose", text: /Still here/
    assert_not_includes response.body, "Gone"

    @root.content_blocks.find_by!(section: section, section_column: 1).update_column(:block_type, "gallery")
    get "/"

    assert_response :success
    assert_select "section.content-section", 0
  end

  # A section whose type is gone can't be drawn as a band, but the blocks in
  # it are ordinary blocks of types that still exist: they stay on the page,
  # once each, in reading order, where the section was.
  test "the blocks of a section whose type is gone are drawn once, stacked in reading order, with no band" do
    asset = processed_asset
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Before the band"))
    section = section_with_texts([ 2, "Right text" ], [ 1, "Left text" ], layout: "three")
    @root.content_blocks.create!(block_type: :image, section: section, section_column: 3, position: 0, media_asset: asset)
    @root.content_blocks.create!(block_type: :rich_text, position: 9, body: rich_doc("After the band"))
    section.update_column(:block_type, "carousel")
    get "/"

    assert_response :success
    assert_select "section.content-section", 0
    assert_select ".content-section__column", 0
    assert_select ".cs-prose", 4
    order = [ "Before the band", "Left text", "Right text", "<img", "After the band" ].map { |text| response.body.index(text) }
    assert_equal order.sort, order
    # Not in a column any more, so the picture is the content width's.
    assert_equal [ Blocks::ImageComponent::SIZES ], css_select("main img[sizes]").map { |img| img["sizes"] }
  end

  test "an image in a column asks for a column-wide picture, and one outside a section for the content width" do
    asset = processed_asset
    @root.content_blocks.create!(block_type: :image, position: 0, media_asset: asset)
    three = @root.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "three" })
    @root.content_blocks.create!(block_type: :image, section: three, section_column: 2, position: 0, media_asset: asset)
    wide = @root.content_blocks.create!(block_type: :section, position: 2, settings: { "layout" => "one_two" })
    @root.content_blocks.create!(block_type: :image, section: wide, section_column: 2, position: 0, media_asset: asset)
    get "/"

    sizes = css_select("img[sizes]").map { |img| img["sizes"] }
    assert_equal [ Blocks::ImageComponent::SIZES, "(min-width: 768px) 245px, (min-width: 480px) 33vw, 100vw", "(min-width: 768px) 491px, (min-width: 480px) 67vw, 100vw" ], sizes
  end

  test "a page of sections costs no query per section or per block in one" do
    asset = processed_asset
    build = lambda do |sections|
      clear_blocks
      sections.times do |index|
        section = @root.content_blocks.create!(block_type: :section, position: index)
        @root.content_blocks.create!(block_type: :image, section: section, section_column: 1, position: 0, media_asset: asset)
        @root.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0, body: rich_doc("Text"))
      end
    end

    build.call(1)
    get "/"
    one = capture_sql { get "/" }.size
    build.call(4)
    get "/"
    four = capture_sql { get "/" }.size

    assert_equal one, four
  end

  # The outline sorts and groups every block of the page: built once for the
  # page (`ThemeHelper#block_outline`) and asked by each section, not built
  # again by each of them.
  test "a page builds one outline however many sections it has" do
    3.times { |index| @root.content_blocks.create!(block_type: :rich_text, section: section_with_texts, section_column: 1, position: index, body: rich_doc("Text #{index}")) }
    built = 0
    original = BlockOutline.method(:new)

    with_singleton_override(BlockOutline, :new, ->(*arguments) { built += 1; original.call(*arguments) }) { get "/" }

    assert_select "section.content-section", 3
    assert_equal 1, built
  end

  test "the body clips what a full-width band lets past the window's edge" do
    get "/"

    assert_select "body.overflow-x-clip"
  end

  test "a code block is drawn with its head and its code coloured, at the top level and in a column of a section" do
    section = @root.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "two" })
    @root.content_blocks.create!(block_type: :code, position: 1, settings: { "language" => "ruby", "filename" => "a.rb", "code" => "def top; end" })
    @root.content_blocks.create!(block_type: :code, position: 0, section: section, section_column: 2, settings: { "language" => "yaml", "code" => "inside: column" })

    get "/"

    assert_response :success
    assert_select "main figure.content-block--code", count: 2
    assert_select "figure.content-block--code .code-file", text: "a.rb"
    assert_select "figure.content-block--code pre span.syn-keyword", text: "def"
    assert_select ".content-section__column figure.content-block--code pre", text: "inside: column"
    assert_select ".content-section__column figure.content-block--code .code-language", text: "YAML"
  end

  # Fences of Markdown in Markdown, 650 deep: what overflowed a request's
  # thread before the depth was counted (`test/values/code_highlight_test.rb`).
  def nested_fences(levels = 650)
    indents = Array.new(levels) { |index| index.zero? ? "" : index.to_s(2).tr("01", " \t") }
    (indents.map { |indent| "#{indent}```md\n" } + [ "x\n" ] + indents.reverse.map { |indent| "#{indent}```\n" }).join
  end

  # Final re-review C1: this page was a 500. The request is made on a thread,
  # as a server makes it; an integration test's own thread is the main one,
  # whose stack is deep enough for the text to lex.
  test "a page that holds a Markdown block of fences nested hundreds deep answers 200 with the code as text, on a thread" do
    code = nested_fences
    @root.content_blocks.create!(block_type: :code, position: 0, settings: { "language" => "markdown", "code" => code })

    Thread.new { get "/" }.join

    assert_response :success
    assert_equal code.delete_suffix("\n"), Nokogiri::HTML5(response.body).at_css("figure.content-block--code pre").text
    assert_select "figure.content-block--code pre span", count: 0
  end

  test "a code block on a live page is read from its published copy: a save shows nothing until it is published, and counts as a change" do
    page = create_page(title: "Docs")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "code", settings: { "language" => "ruby", "code" => "first = 1" } }).record
    publish_changes(page)
    path = PublicSite::Urls.new.path_for(page, "en")

    assert ContentBlocks::Save.call(block, attributes: { settings: { "code" => "second = 2" } }).ok?
    get path

    assert_select "figure.content-block--code pre", text: "first = 1"
    assert page.reload.unpublished_changes_at.present?, "a save on a live page marks it"
    assert_equal [ :changed ], Publishing::Changes.of(page).blocks.map(&:kind)
    assert_equal "ruby", block.reload.settings["language"], "a save of the code alone leaves the other settings"

    publish_changes(page)
    get path
    assert_select "figure.content-block--code pre", text: "second = 2"
  end

  test "an empty code block draws nothing on the page" do
    @root.content_blocks.create!(block_type: :code, position: 0)

    get "/"

    assert_response :success
    assert_select "figure.content-block--code", count: 0
  end
end
