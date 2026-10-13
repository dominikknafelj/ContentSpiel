require "test_helper"

# `PostGraph::Rows` (pages in the mind graph, spec §3, decision 10): the rows
# of the list's two filters, each a post's node as the graph's data has it.
class PostGraph::RowsTest < ActiveSupport::TestCase
  def rows(actor: nil, limit: PostGraph::ROW_LIMIT) = PostGraph::Rows.new(actor: actor, limit: limit, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })

  def list_block(page, **settings)
    ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: settings.stringify_keys)
  end

  setup do
    @blog = create_page(title: "Blog")
    list_block(@blog, content_type: "blog", tag: "news")
    @listed = create_post(title: "Listed", tags: [ "news" ])
    @old = create_post(title: "Old").tap { |post| post.update_columns(published_at: 2.days.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    @new = create_post(title: "New", published: false)
  end

  test "unlisted is the readable posts no readable page lists, newest first, each a whole post node with no line" do
    result = rows.unlisted

    assert_equal 2, result[:total]
    assert_equal [ "post-#{@new.id}", "post-#{@old.id}" ], result[:rows].map { |row| row[:id] }
    assert_equal({ id: "post-#{@new.id}", title: "New", type: "blog", colour_index: ContentTypes.fetch("blog").colour_index, status: "draft", changes: nil,
                   change_at: nil, listed: false, url: "/cs-studio/posts/#{@new.id}", degree: 0, related_count: 0, tag_count: 0, open_notes: 0 }, result[:rows].first)
  end

  test "the first rows up to the limit, with the whole total" do
    assert_equal [ 2, [ "post-#{@new.id}" ] ], [ rows(limit: 1).unlisted[:total], rows(limit: 1).unlisted[:rows].map { |row| row[:id] } ]
  end

  # The fixtures' author reads every post and, here, one branch of the tree
  # that does not hold the page that lists "Listed".
  test "unlisted is true for the viewer: a post only a page they cannot read lists is a row, and a trashed post is none" do
    other = create_page(title: "Other")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ other.id ] })
    @old.update_column(:trashed_at, Time.current)

    result = as(users(:author)) { rows(actor: users(:author)).unlisted }

    assert_equal [ @listed, @new ].map { |post| "post-#{post.id}" }.sort, result[:rows].map { |row| row[:id] }.sort
    assert_equal 2, result[:total]
    assert_equal [ "post-#{@new.id}" ], rows.unlisted[:rows].map { |row| row[:id] }, "to someone who reads the whole tree it is listed"
  end

  test "listed is the posts one target of a page brings in beyond the twenty its local view draws, each with that target, and the filter of the target's block" do
    posts = 22.times.map { |index| create_post(title: "News #{index}", tags: [ "news" ]) }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).minutes.from_now) } # version: none (a test sets a time) # changes: none (a test sets a time)

    news = "tag-#{Tag.find_by!(name: "news").id}"
    result = rows.listed(@blog.id, news)

    assert_equal 3, result[:total], "twenty-three listed, twenty drawn"
    assert_equal [ posts[1], posts[0], @listed ].map { |post| "post-#{post.id}" }, result[:rows].map { |row| row[:id] }
    assert_equal({ type: "blog", tag: "news" }, result[:filter])
    assert result[:rows].all? { |row| row[:listed] }
    assert_equal [ news ], result[:rows].map { |row| row[:via] }.uniq, "a block with a tag and a type points at the tag"
    assert(rows.unlisted[:rows].none? { |row| row.key?(:via) })
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(@blog.id, "type-blog"), "a target the page does not list has no pill and no rows")
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(@blog.id, "<junk>"))
  end

  test "a page that lists twenty or fewer has no rows, and a page with no list block an empty filter" do
    assert_equal({ total: 0, rows: [], filter: { type: "blog", tag: "news" } }, rows.listed(@blog.id, "tag-#{Tag.find_by!(name: "news").id}"))
    assert_equal({ total: 0, rows: [], filter: {} }, rows.listed(root_page.id, "all-posts"))
  end

  test "each read costs eight statements, with a few rows and with thirty more" do
    viewer = users(:one)
    22.times { |index| create_post(title: "News #{index}", tags: [ "news" ]) } # so that `listed` has rows: a read with none asks for no notes
    news = "tag-#{Tag.find_by!(name: "news").id}" # looked up out here: inside the block it would be counted
    count = -> { [ capture_sql { rows(actor: viewer).unlisted }.size, capture_sql { rows(actor: viewer).listed(@blog.id, news) }.size ] }

    few = count.call
    30.times { |index| create_post(title: "More #{index}", tags: ([ "news" ] if index.even?).to_a) }

    assert_equal [ 8, 8 ], few
    assert_equal [ 8, 8 ], count.call
  end

  # A viewer who is not an owner costs one more in a request, constant:
  # their grants, read once. Here they are read before the counting (the
  # first read of the test), so each read is its eight.
  test "for a viewer with a scope each read costs the same eight statements at both sizes, after their grants, and holds no post outside it" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    author = users(:author)
    mine = ->(title, **options) { create_post(title: title, **options).tap { |post| post.update_column(:author_id, author.id) } }
    22.times { |index| mine.call("Mine #{index}", tags: [ "news" ]) }
    mine.call("Mine alone")
    news = "tag-#{Tag.find_by!(name: "news").id}"
    assert_equal 9, capture_sql { as(author) { rows(actor: author).unlisted } }.size, "the grants, once"
    read = -> { as(author) { [ capture_sql { @unlisted = rows(actor: author).unlisted }.size, capture_sql { @behind = rows(actor: author).listed(@blog.id, news) }.size ] } }

    few = read.call
    assert_equal [ 1, 2 ], [ @unlisted[:total], @behind[:total] ], "of the twenty-two they read, two are behind the pill; the three posts of others are in neither read"
    30.times { |index| mine.call("More #{index}", tags: ([ "news" ] if index.even?).to_a) }

    assert_equal [ 8, 8 ], few
    assert_equal [ 8, 8 ], read.call
    assert_equal [ 16, 17 ], [ @unlisted[:total], @behind[:total] ]
    assert_no_match(/Listed|Old|New\b/, [ @unlisted, @behind ].to_json)
  end
end
