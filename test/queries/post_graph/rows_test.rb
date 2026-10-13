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
                   change_at: nil, listed: false, url: "/cs-studio/posts/#{@new.id}", degree: 0, related_count: 0, tag_count: 0, open_notes: 0, unconnected: true }, result[:rows].first)
  end

  # The whole graph's notice counts the posts with no connection as not
  # shown; a row that adds such a post takes it out of that count, so the
  # row says which it is, by the rule `Global` ranks with. Held against
  # `Global` itself: the posts it counts as connected are exactly the rows
  # that are not unconnected, at a cap that cuts every one of them too.
  test "an unlisted row says whether its post has no connection at all, by the rule the whole graph counts with, also for a post the cap cut" do
    related = create_post(title: "Related", content_type: "resume_entry")
    other = create_post(title: "Other end", content_type: "resume_entry")
    PostRelation.create!(post: other, related_post: related)
    twins = 2.times.map { |index| create_post(title: "Twin #{index}", content_type: "resume_entry", tags: [ "pair" ]) }
    single = create_post(title: "Single tag", content_type: "resume_entry", tags: [ "lonely" ])
    # A tag a page lists (for blog posts) that this one post alone carries: it
    # is no blog post, so no page lists it, and the listed tag is a node, so
    # it has a line.
    list_block(@blog, content_type: "blog", tag: "solo")
    create_post(title: "Carries a listed tag", content_type: "resume_entry", tags: [ "solo" ])
    hidden = create_post(title: "Trashed end", content_type: "resume_entry")
    PostRelation.create!(post: single, related_post: hidden)
    hidden.update_column(:trashed_at, Time.current)

    flags = rows.unlisted[:rows].to_h { |row| [ row[:title], row[:unconnected] ] }

    assert_equal({ "Related" => false, "Other end" => false, "Twin 0" => false, "Twin 1" => false, "Carries a listed tag" => false,
                   "Single tag" => true, "Old" => true, "New" => true }, flags,
      "a relation either way, a tag two readable posts carry and a tag a page lists are connections; a tag one post carries and a relation to a trashed post are none")
    assert rows.listed(@blog.id, "tag-#{Tag.find_by!(name: "news").id}")[:rows].none? { |row| row.key?(:unconnected) }, "a pill's rows say nothing of it: they are counted by their pill"

    whole = PostGraph::Global.call(actor: nil, url_for: ->(_record) { "" }, everything: true)
    cut = PostGraph::Global.call(actor: nil, url_for: ->(_record) { "" }, everything: true, cap: 1)
    unlisted = rows.unlisted[:rows]
    drawn = whole[:nodes].map { |node| node[:id] }
    assert_equal unlisted.reject { |row| row[:unconnected] }.map { |row| row[:id] }.sort, (unlisted.map { |row| row[:id] } & drawn).sort, "the rows that are connected are the ones the whole graph draws"
    assert_equal [ whole[:isolated], 1 ], [ cut[:isolated], cut[:shown] ], "the cap cuts connected posts and leaves the unconnected count as it is"
    assert_equal whole[:isolated], unlisted.count { |row| row[:unconnected] }, "every unconnected post here is unlisted, and each row says so"
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

  # EACH FIGURE IS A CEILING (the site's five and the nodes' three; the
  # unlisted read asks one more, the relations that touch its rows, for
  # what each row says of its post's connections). The two sizes
  # differ in the pages (and their children), the list blocks on a page, a
  # section, the tags blocks name, the posts and their notes: a statement
  # per page, per block or per row would show.
  test "the unlisted read costs nine statements and a pill's eight, on a small site and on one with thirty more pages, their blocks and sections, and thirty more posts" do
    viewer = users(:one)
    22.times { |index| create_post(title: "News #{index}", tags: [ "news" ]) } # so that `listed` has rows: a read with none asks for no notes
    news = "tag-#{Tag.find_by!(name: "news").id}" # looked up out here: inside the block it would be counted
    count = -> { [ capture_sql { @unlisted = rows(actor: viewer).unlisted }.size, capture_sql { @behind = rows(actor: viewer).listed(@blog.id, news) }.size ] }

    few = count.call
    assert_equal [ 2, 3 ], [ @unlisted[:total], @behind[:total] ]
    30.times do |index|
      page = create_page(title: "Page #{index}", parent: index.even? ? @blog : root_page)
      list_block(page, tag: "topic #{index % 6}")
      section = ContentBlock.create!(owner: page, block_type: :section, position: 5, settings: { "layout" => "two" })
      ContentBlock.create!(owner: page, block_type: :post_list, position: 0, section_id: section.id, section_column: 2, settings: { "content_type" => "resume_entry", "tag" => "news" })
    end
    list_block(@blog, tag: "topic 0")
    posts = 30.times.map { |index| create_post(title: "More #{index}", tags: index.even? ? [ "news" ] : (index % 3 == 0 ? [ "topic #{index % 6}" ] : [])) }
    as(users(:two)) { posts.last(4).each { |post| Notes::Start.call(post, body: "A note") } }

    assert_equal [ 9, 8 ], few
    assert_equal [ 9, 8 ], count.call
    assert_equal [ 12, 18 ], [ @unlisted[:total], @behind[:total] ]
  end

  # The exact count at a plain shape, named: with no row to answer, the
  # nodes' three are not asked for, and on a site where no list block names
  # a tag neither are the tags blocks name.
  test "a read with no row costs the site's statements alone: five, and four on a site where no block names a tag" do
    viewer = users(:one)
    @old.update_column(:trashed_at, Time.current)
    @new.update_column(:trashed_at, Time.current)
    count = -> { [ capture_sql { @unlisted = rows(actor: viewer).unlisted }.size, capture_sql { @behind = rows(actor: viewer).listed(@blog.id, "type-blog") }.size ] }

    assert_equal [ 5, 5 ], count.call
    assert_equal [ 0, 0 ], [ @unlisted[:total], @behind[:total] ]
    @blog.content_blocks.destroy_all
    assert_equal 4, capture_sql { rows(actor: viewer).listed(@blog.id, "type-blog") }.size
  end

  # Review m5: as `Local` answers for a focus that went meanwhile.
  test "listed for a page trashed after the caller found it is not found, not an empty answer" do
    @blog.update_column(:trashed_at, Time.current)

    assert_raises(ActiveRecord::RecordNotFound) { rows.listed(@blog.id, "tag-#{Tag.find_by!(name: "news").id}") }
    assert_raises(ActiveRecord::RecordNotFound) { rows.listed(0, "all-posts") }
  end

  # A viewer who is not an owner costs one more in a request, constant:
  # their grants, read once. Here they are read before the counting (the
  # first read of the test), so each read is its nine or its eight.
  test "for a viewer with a scope the reads cost the same nine and eight statements at both sizes, after their grants, and hold no post outside it" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    author = users(:author)
    mine = ->(title, **options) { create_post(title: title, **options).tap { |post| post.update_column(:author_id, author.id) } }
    22.times { |index| mine.call("Mine #{index}", tags: [ "news" ]) }
    mine.call("Mine alone")
    news = "tag-#{Tag.find_by!(name: "news").id}"
    assert_equal 10, capture_sql { as(author) { rows(actor: author).unlisted } }.size, "the grants, once"
    read = -> { as(author) { [ capture_sql { @unlisted = rows(actor: author).unlisted }.size, capture_sql { @behind = rows(actor: author).listed(@blog.id, news) }.size ] } }

    few = read.call
    assert_equal [ 1, 2 ], [ @unlisted[:total], @behind[:total] ], "of the twenty-two they read, two are behind the pill; the three posts of others are in neither read"
    30.times { |index| mine.call("More #{index}", tags: ([ "news" ] if index.even?).to_a) }

    assert_equal [ 9, 8 ], few
    assert_equal [ 9, 8 ], read.call
    assert_equal [ 16, 17 ], [ @unlisted[:total], @behind[:total] ]
    assert_no_match(/Listed|Old|New\b/, [ @unlisted, @behind ].to_json)
    assert_no_match(/#{[ @listed, @old, @new ].map { |post| "post-#{post.id}\\b" }.join("|")}/, [ @unlisted, @behind ].to_json, "nor their ids")
  end
end
