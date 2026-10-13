require "test_helper"

# `PostGraph::Listings` (pages in the mind graph, spec §1): which page lists
# what, from the list blocks' settings, and which posts that is.
class PostGraph::ListingsTest < ActiveSupport::TestCase
  # A block that names a type nobody registers any more cannot be saved (the
  # field validates its value), and exists all the same: it was saved while
  # the type was there. So such a name is stored around the validation.
  def list_block(page, **settings)
    stored = settings.stringify_keys
    retired = stored["content_type"].present? && ContentTypes.find(stored["content_type"]).nil?
    block = ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: retired ? stored.except("content_type") : stored)
    block.update_column(:settings, stored) if retired
    block
  end

  def listings(pages = Page.all)
    posts = Post.kept.pluck(:id, :content_type, :published_at, :updated_at)
    links = PostTag.where(post_id: Post.kept.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
    PostGraph::Listings.new(page_ids: pages.map(&:id), post_rows: posts, tag_links: links)
  end

  def tag(name) = "tag-#{Tag.find_by!(name: name).id}"

  setup do
    @ruby = create_post(title: "Ruby", tags: [ "ruby" ])
    @plain = create_post(title: "Plain")
    @entry = create_post(title: "Entry", content_type: "resume_entry", tags: [ "ruby" ])
    @draft = create_post(title: "Draft", published: false)
    @page = create_page(title: "Listing")
  end

  test "a block's target is its tag, else its type, else All posts" do
    by_tag = create_page(title: "By tag")
    by_type = create_page(title: "By type")
    list_block(@page)
    list_block(by_tag, tag: "ruby", content_type: "blog")
    list_block(by_type, content_type: "blog")

    result = listings

    assert_equal [ "all-posts" ], result.targets(@page.id)
    assert_equal [ tag("ruby") ], result.targets(by_tag.id), "a block with a tag and a type points at the tag"
    assert_equal [ "type-blog" ], result.targets(by_type.id)
    assert_equal [ by_tag.id ], result.pages_of(tag("ruby"))
    assert_equal Set[Tag.find_by!(name: "ruby").id], result.tag_ids
  end

  test "a block names its tag whatever the case and the spaces, and a name no tag has makes no line" do
    list_block(@page, tag: "  RUBY ")
    other = create_page(title: "Other")
    list_block(other, tag: "nothing-has-this")

    result = listings

    assert_equal [ tag("ruby") ], result.targets(@page.id)
    assert_empty result.targets(other.id)
    assert_empty result.posts_of(other.id)
    assert_equal [ [ @page.id, tag("ruby") ] ], result.edges
  end

  # An old row or a write around the model: two tags one name apart only in
  # case. The listing finds both by the name (`Tag.named`), so this does.
  test "two tags whose names differ only in case are one name: the page lists the posts of both, and its line goes to the older tag" do
    older = Tag.find_by!(name: "ruby")
    newer = Tag.create!(name: "ruby twin")
    newer.update_column(:name, "Ruby")
    twin = create_post(title: "Twin")
    PostTag.create!(post: twin, tag: newer)
    list_block(@page, tag: "ruby")

    result = listings

    assert_equal BlockTypes::PostList.listed_posts(@page.content_blocks.first.settings_object, include_unpublished: true).pluck(:id).sort, result.posts_of(@page.id).sort
    assert_includes result.posts_of(@page.id), twin.id
    assert_equal [ "tag-#{older.id}" ], result.targets(@page.id)
    assert_equal Set[older.id], result.tag_ids
  end

  test "two blocks with one target are one line, and two targets are two" do
    list_block(@page, content_type: "blog")
    list_block(@page, content_type: "blog")
    list_block(@page, tag: "ruby")

    assert_equal [ "type-blog", tag("ruby") ].sort, listings.targets(@page.id).sort
  end

  test "a block in a section belongs to its page" do
    section = ContentBlock.create!(owner: @page, block_type: :section, position: 0, settings: { "layout" => "two" })
    ContentBlock.create!(owner: @page, block_type: :post_list, position: 0, section_id: section.id, section_column: 1, settings: { "content_type" => "blog" })

    assert_equal [ "type-blog" ], listings.targets(@page.id)
  end

  test "a retired type a block names is still a target, and lists no post" do
    list_block(@page, content_type: "gone/thing")
    @plain.update_column(:content_type, "gone/thing")

    result = listings

    assert_equal [ "type-gone/thing" ], result.targets(@page.id)
    assert_empty result.posts_of(@page.id)
    assert_equal 1, result.type_count("gone/thing")
    assert_equal 3, result.post_count, "a post of a retired type is one no block with no filter lists"
  end

  test "a block of another type and a page that is not asked for make no line" do
    other = create_page(title: "Other")
    list_block(other, content_type: "blog")
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0)

    assert_empty listings([ @page ]).edges
  end

  # The parity the spec asks for: for every shape of settings, the posts
  # this object says a page lists are the posts the listing itself lists.
  test "the posts a page lists are the listing's own, for every shape of settings" do
    @plain.update_column(:content_type, "gone/thing")
    shapes = [ {}, { content_type: "blog" }, { tag: "ruby" }, { tag: " Ruby " }, { content_type: "resume_entry", tag: "ruby" },
               { content_type: "blog", tag: "nothing-has-this" }, { content_type: "gone/thing" } ]
    pages = shapes.each_with_index.map { |shape, index| create_page(title: "Shape #{index}").tap { |page| list_block(page, **shape) } }

    result = listings

    pages.zip(shapes).each do |page, shape|
      expected = BlockTypes::PostList.listed_posts(page.content_blocks.first.settings_object, include_unpublished: true).pluck(:id)
      assert_equal expected.sort, result.posts_of(page.id).sort, shape.inspect
      assert_equal expected.size, result.listed_count(page.id), shape.inspect
    end
  end

  test "a page's posts come newest first, a draft by when it was last changed" do
    list_block(@page)
    @ruby.update_columns(published_at: 3.days.ago)   # version: none (a test sets a time) # changes: none (a test sets a time)
    @entry.update_columns(published_at: 1.day.ago)   # version: none (a test sets a time) # changes: none (a test sets a time)
    @plain.update_columns(published_at: 2.days.ago)  # version: none (a test sets a time) # changes: none (a test sets a time)
    @draft.update_columns(updated_at: 1.hour.ago)    # version: none (a test sets a time) # changes: none (a test sets a time)

    assert_equal [ @draft.id, @entry.id, @plain.id, @ruby.id ], listings.posts_of(@page.id)
  end

  # Third design answers: in a page's local view the hub that brings a post
  # in draws a line to it. Which hub that is, is the first block's that lists it.
  test "the target that brings a post in is the first list block's that lists it, and none for a post the page does not list" do
    list_block(@page, tag: "nothing-has-this")
    list_block(@page, tag: "ruby")
    list_block(@page, content_type: "blog")
    list_block(@page)

    result = listings

    assert_equal tag("ruby"), result.target_of(@page.id, @ruby.id), "the tag's block comes before the type's"
    assert_equal "type-blog", result.target_of(@page.id, @plain.id)
    assert_equal tag("ruby"), result.target_of(@page.id, @entry.id)
    assert_nil result.target_of(create_page(title: "Other").id, @ruby.id)
    @plain.update_column(:content_type, "resume_entry")
    assert_equal "all-posts", listings.target_of(@page.id, @plain.id), "only the block with no filter lists it now"
  end

  # Design answer H1: one pill per target, each counting only what that
  # target brings in beyond the posts the view draws.
  test "what is left out is counted per target, by the target that brings each post in, and each target has its own block's filter" do
    list_block(@page, tag: "pill")
    list_block(@page, content_type: "resume_entry")
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)

    result = listings

    # The setup's @entry, published a moment ago, is the newest; then the
    # hours alternate. The twenty newest: @entry, ten pills, nine entries.
    assert_equal 31, result.listed_count(@page.id)
    assert_equal({ tag("pill") => 5, "type-resume_entry" => 6 }, result.left_out(@page.id))
    assert_equal pills.last(5).map(&:id), result.left_out_of(@page.id, tag("pill"))
    assert_equal entries.last(6).map(&:id), result.left_out_of(@page.id, "type-resume_entry")
    assert_empty result.left_out_of(@page.id, "type-blog")
    assert_empty result.left_out(create_page(title: "Other").id)
    assert_equal({ type: nil, tag: "pill" }, result.filter_of(@page.id, tag("pill")))
    assert_equal({ type: "resume_entry", tag: nil }, result.filter_of(@page.id, "type-resume_entry"))
    assert_equal({ type: nil, tag: "pill" }, result.filter_of(@page.id), "with no target, the first block's")
    assert_equal({}, result.filter_of(@page.id, "type-blog"))
  end

  test "listed and unlisted are each other's rest, and with no list block every post is unlisted" do
    assert_equal [ @ruby, @plain, @entry, @draft ].map(&:id).sort, listings.unlisted.sort

    list_block(@page, content_type: "blog")
    result = listings

    assert result.listed?(@ruby.id)
    assert_not result.listed?(@entry.id)
    assert_equal [ @entry.id ], result.unlisted
    assert_equal({ type: "blog", tag: nil }, result.filter_of(@page.id))
    assert_equal({}, result.filter_of(create_page(title: "None").id))
    assert_equal [ 3, 1, 4 ], [ result.type_count("blog"), result.type_count("resume_entry"), result.post_count ]
  end

  # Two sizes far apart, so a statement per page, per block or per post
  # cannot hide: 3 pages with a block each and 5 posts, then 30 and 60.
  test "it costs two statements whatever the number of pages, blocks and posts" do
    list_block(@page, tag: "ruby")
    list_block(create_page(title: "Small"), content_type: "blog")
    create_post(title: "Small post", tags: [ "ruby" ])
    ask = -> do
      posts = Post.kept.pluck(:id, :content_type, :published_at, :updated_at)
      links = PostTag.pluck(:tag_id, :post_id)
      page_ids = Page.pluck(:id)
      statements = capture_sql do
        result = PostGraph::Listings.new(page_ids: page_ids, post_rows: posts, tag_links: links)
        result.edges
        result.tag_ids
        page_ids.each { |id| result.posts_of(id) }
        page_ids.each { |id| result.target_of(id, posts.first.first) }
        page_ids.each { |id| result.left_out(id) }
        page_ids.each { |id| result.filter_of(id) }
        result.unlisted
        result.post_count
      end
      [ page_ids.size, posts.size, statements ]
    end

    few_pages, few_posts, few = ask.call
    27.times { |index| list_block(create_page(title: "More #{index}"), tag: index.even? ? "ruby" : "tag #{index}", content_type: "blog") }
    55.times { |index| create_post(title: "Post #{index}", tags: [ "ruby", "tag #{index}" ]) }
    many_pages, many_posts, many = ask.call

    assert_equal [ 3, 5, 30, 60 ], [ few_pages, few_posts, many_pages, many_posts ]
    assert_equal 2, few.size, few.join("\n")
    assert_equal 2, many.size, many.join("\n")
  end
end
