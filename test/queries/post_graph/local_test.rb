require "test_helper"

# `PostGraph::Local` (mind graph canvas spec §3.3): a post's or a tag's
# neighbourhood, one level per depth, over both kinds of connection.
class PostGraph::LocalTest < ActiveSupport::TestCase
  def local(focus, depth: 1, actor: nil, cap: PostGraph::CAP)
    PostGraph::Local.call(actor: actor, focus: focus, depth: depth, cap: cap, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })
  end

  def post_focus(post, actor: nil) = PostGraph::Focus.find(actor: actor, post: post.id)
  def tag_focus(name, actor: nil) = PostGraph::Focus.find(actor: actor, tag: Tag.find_by!(name: name).id)
  def relate(a, b) = PostRelation.create!(post: a, related_post: b)
  def ids(result) = result[:nodes].map { |n| n[:id] }.sort
  def tag_names(result) = result[:tags].map { |t| t[:name] }.sort
  def pid(post) = "post-#{post.id}"
  def page_focus(page, actor: nil) = PostGraph::Focus.find(actor: actor, page: page.id)
  def page_ids(result) = result[:pages].map { |page| page[:id] }

  # As in `global_test.rb`: a block that names a type nobody registers any
  # more is stored around the validation.
  def list_block(page, **settings)
    stored = settings.stringify_keys
    retired = stored["content_type"].present? && ContentTypes.find(stored["content_type"]).nil?
    block = ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: retired ? stored.except("content_type") : stored)
    block.update_column(:settings, stored) if retired
    block
  end

  setup do
    #   centre -- near -- far -- beyond
    #   centre, cousin share "shared"; far, cousin share "outer"; centre alone has "solo"
    @centre = create_post(title: "Centre", tags: %w[shared solo])
    @near = create_post(title: "Near")
    @far = create_post(title: "Far", tags: %w[outer])
    @beyond = create_post(title: "Beyond")
    @cousin = create_post(title: "Cousin", tags: %w[shared outer])
    relate(@centre, @near)
    relate(@far, @near) # stored the other way round on purpose: relations read as undirected
    relate(@far, @beyond)
  end

  test "depth 1 from a post: its related posts and its shared tags, not the tags' other posts" do
    result = local(post_focus(@centre))

    assert_equal [ pid(@centre), pid(@near) ].sort, ids(result)
    assert_equal %w[shared], tag_names(result), "a tag on one readable post is no node"
    assert_equal({ kind: "post", id: @centre.id, node_id: pid(@centre), title: "Centre", depth: 1 }, result[:focus])
    assert_equal 2, result[:tags].first[:count], "the readable count, not the one drawn post"
    assert_equal 1, result[:tags].first[:degree]
  end

  test "depth 2 from a post adds the neighbours' neighbours and the tags' other posts" do
    result = local(post_focus(@centre), depth: 2)

    assert_equal [ pid(@centre), pid(@near), pid(@far), pid(@cousin) ].sort, ids(result)
    assert_not_includes ids(result), pid(@beyond)
    assert_includes tag_names(result), "shared"
    assert_equal 2, result[:focus][:depth]
  end

  test "depth 1 from a tag: the posts that carry it; depth 2: their related posts and other tags" do
    one = local(tag_focus("shared"))
    two = local(tag_focus("shared"), depth: 2)

    assert_equal [ pid(@centre), pid(@cousin) ].sort, ids(one)
    assert_equal %w[shared], tag_names(one)
    assert_equal [ pid(@centre), pid(@cousin), pid(@near) ].sort, ids(two)
    assert_equal %w[outer shared], tag_names(two)
    assert_equal "tag-#{Tag.find_by!(name: "shared").id}", two[:focus][:node_id]
  end

  test "a focused tag is a node even with one readable post" do
    result = local(tag_focus("solo"))

    assert_equal [ pid(@centre) ], ids(result)
    assert_equal %w[solo], tag_names(result)
    assert_equal 1, result[:tags].first[:count]
  end

  test "a depth other than 2 is 1" do
    assert_equal 1, local(post_focus(@centre), depth: 7)[:focus][:depth]
    assert_equal 1, local(post_focus(@centre), depth: "x")[:focus][:depth]
    assert_equal 2, local(post_focus(@centre), depth: "2")[:focus][:depth]
  end

  test "every edge is between two drawn nodes, and degrees count them" do
    result = local(post_focus(@centre), depth: 2)
    node_ids = ids(result) + result[:tags].map { |t| t[:id] }

    assert result[:edges].all? { |edge| node_ids.include?(edge[:source]) && node_ids.include?(edge[:target]) }
    centre = result[:nodes].find { |n| n[:id] == pid(@centre) }
    assert_equal result[:edges].count { |edge| edge[:source] == pid(@centre) || edge[:target] == pid(@centre) }, centre[:degree]
    assert_equal result[:edges].count { |edge| edge[:kind] == "related" && [ edge[:source], edge[:target] ].include?(pid(@centre)) }, centre[:related_count]
    assert_equal result[:edges].count { |edge| edge[:kind] == "tag" && edge[:source] == pid(@centre) }, centre[:tag_count]
  end

  test "over the cap the focus stays, nearer posts come first, and total says how many there were" do
    result = local(post_focus(@centre), depth: 2, cap: 2)

    assert_equal [ pid(@centre), pid(@near) ].sort, ids(result)
    assert_equal 4, result[:total]
    assert_equal 2, result[:shown]
  end

  test "an unreadable or trashed neighbour is no node, no edge, and not in a tag's count" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    [ @centre, @near ].each { |post| post.update_column(:author_id, users(:author).id) }

    result = as(users(:author)) { local(post_focus(@centre, actor: users(:author)), depth: 2, actor: users(:author)) }

    assert_equal [ pid(@centre), pid(@near) ].sort, ids(result)
    assert_empty result[:tags], "'shared' has one readable post for this viewer"

    @near.update_column(:trashed_at, Time.current)
    assert_equal [ pid(@centre) ], ids(local(post_focus(@centre)))
  end

  test "the number of statements depends on the depth, not on the neighbourhood's size" do
    few = capture_sql { local(post_focus(@centre), depth: 2) }.size
    6.times { |i| relate(@centre, create_post(title: "More #{i}", tags: %w[shared])) }
    many = capture_sql { local(post_focus(@centre), depth: 2) }.size

    assert_equal few, many
  end

  # A PAGE AS THE FOCUS (pages in the mind graph, spec §7). Each test makes
  # its own pages: the file's `setup` is about posts.
  #
  #   Home ── Docs ── Guide ── Intro
  #        │       └─ Reference
  #        └─ Blog
  def tree
    @docs = create_page(title: "Docs")
    @guide = create_page(title: "Guide", parent: @docs)
    @intro = create_page(title: "Intro", parent: @guide)
    @reference = create_page(title: "Reference", parent: @docs)
    @blog = create_page(title: "Blog")
  end

  test "depth 1 around a page: its parent, its children and what its blocks list, and no post" do
    tree
    list_block(@docs, tag: "shared")
    list_block(@docs, content_type: "resume_entry")

    result = local(page_focus(@docs))

    assert_equal [ root_page, @docs, @guide, @reference ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_equal [ "tag-#{Tag.find_by!(name: "shared").id}" ], result[:tags].map { |tag| tag[:id] }
    assert_equal [ "type-resume_entry" ], result[:types].map { |type| type[:id] }
    assert_empty result[:nodes]
    assert_equal({ kind: "page", id: @docs.id, node_id: "page-#{@docs.id}", title: "Docs", depth: 1 }, result[:focus])
    assert_equal 3, result[:edges].count { |edge| edge[:kind] == "tree" }
    assert_equal 2, result[:edges].count { |edge| edge[:kind] == "lists" }
    assert_nil result[:more]
  end

  test "depth 2 around a page adds the grandparent, the siblings and the grandchildren, each with its tree line" do
    tree

    result = local(page_focus(@guide), depth: 2)

    assert_equal [ root_page, @docs, @guide, @intro, @reference ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_not_includes page_ids(result), "page-#{@blog.id}", "the grandparent's other child is three steps away"
    assert_equal 4, result[:edges].count { |edge| edge[:kind] == "tree" }
  end

  # Third design answers, "Local view lines": the hub that brings a post in
  # draws the line to it, and more hangs off the hub. No lists line joins
  # the page to a post.
  test "depth 2 around a page draws the twenty newest posts it lists, each joined to the hub that brings it in, and counts the rest behind more" do
    tree
    list_block(@blog, content_type: "resume_entry")
    posts = 23.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)

    result = local(page_focus(@blog), depth: 2)

    assert_equal posts.first(20).map { |post| "post-#{post.id}" }.sort, ids(result)
    assert_equal [ { id: "more-type-resume_entry", count: 3, page: "page-#{@blog.id}", target: "type-resume_entry" } ], result[:more]
    lists = result[:edges].select { |edge| edge[:kind] == "lists" }
    brings = result[:edges].select { |edge| edge[:kind] == "brings" }
    assert_equal [ { source: "page-#{@blog.id}", target: "type-resume_entry", kind: "lists" } ], lists, "the page's one lists line, and none to a post"
    assert_equal 21, brings.size, "twenty posts and the pill"
    assert brings.all? { |edge| edge[:source] == "type-resume_entry" }
    assert_includes brings, { source: "type-resume_entry", target: "more-type-resume_entry", kind: "brings" }
    assert_equal ids(result), (brings.map { |edge| edge[:target] } - [ "more-type-resume_entry" ]).sort
    assert_equal [ 20, 20 ], result.values_at(:total, :shown)
    assert_empty local(page_focus(@blog), depth: 1)[:nodes]
    assert_empty local(page_focus(@blog), depth: 1)[:edges].select { |edge| edge[:kind] == "brings" }
  end

  test "a post the page lists through a tag is joined to the tag by its own line and by no other" do
    tree
    list_block(@blog, tag: "shared")

    result = local(page_focus(@blog), depth: 2)
    tag = "tag-#{Tag.find_by!(name: "shared").id}"

    assert_equal [ @centre, @cousin ].map { |post| "post-#{post.id}" }.sort, ids(result)
    assert_includes result[:edges], { source: "post-#{@centre.id}", target: tag, kind: "tag" }
    assert_empty result[:edges].select { |edge| edge[:kind] == "brings" }, "the tag is the hub, and its own line is the line"
    assert_empty result[:edges].select { |edge| edge[:kind] == "lists" && edge[:target].start_with?("post-") }
    assert_nil result[:more]
  end

  # Design answer H1: ONE PILL PER TARGET, each counting only what its own
  # target brings in. Not one pill on the first block's hub.
  test "a page with two list blocks has a pill per target, each on its own hub or tag with its own count, and a target that brings in nothing more has none" do
    tree
    list_block(@docs, tag: "pill")
    list_block(@docs, content_type: "resume_entry")
    list_block(@docs, tag: "few")
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    create_post(title: "Few", tags: [ "few" ]).update_columns(published_at: 1.minute.ago)                  # version: none (a test sets a time) # changes: none (a test sets a time)
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    pill = "tag-#{Tag.find_by!(name: "pill").id}"

    result = local(page_focus(@docs), depth: 2)

    # The twenty newest: "Few", ten pills and nine entries. Left out: five
    # pills and six entries.
    assert_equal [ { id: "more-#{pill}", count: 5, page: "page-#{@docs.id}", target: pill },
                   { id: "more-type-resume_entry", count: 6, page: "page-#{@docs.id}", target: "type-resume_entry" } ], result[:more], "in the order of the page's targets; the tag few has no pill"
    to_pills = result[:edges].select { |edge| edge[:target].start_with?("more-") }
    assert_equal [ { source: pill, target: "more-#{pill}", kind: "brings" }, { source: "type-resume_entry", target: "more-type-resume_entry", kind: "brings" } ], to_pills
    assert_equal 9, result[:edges].count { |edge| edge[:kind] == "brings" && edge[:target].start_with?("post-") }, "the nine entries hang off the type; the tagged posts have their tag lines"
  end

  # A lists line is drawn between two nodes of the view: a neighbour page
  # keeps its line to a target the focus reaches too, and what only the
  # neighbour lists is no node here (it is one step further).
  test "around a page a neighbour's lists line is drawn only to a target of the focus, and what only the neighbour lists is no node" do
    tree
    list_block(@docs, content_type: "resume_entry")
    list_block(@guide, content_type: "resume_entry")
    list_block(@guide, tag: "shared")
    list_block(@reference)

    result = local(page_focus(@docs), depth: 2)

    assert_equal [ "type-resume_entry" ], result[:types].map { |type| type[:id] }
    assert_empty result[:tags]
    assert_equal [ [ "page-#{@docs.id}", "type-resume_entry" ], [ "page-#{@guide.id}", "type-resume_entry" ] ],
                 result[:edges].select { |edge| edge[:kind] == "lists" }.map { |edge| edge.values_at(:source, :target) }
    assert_empty result[:nodes], "the neighbours' posts are not the focus's"
  end

  test "a page that lists by nothing brings its posts in through All posts, pill included" do
    tree
    list_block(@blog)
    21.times { |index| create_post(title: "Many #{index}") }

    all = local(page_focus(@blog), depth: 2)
    brings = all[:edges].select { |edge| edge[:kind] == "brings" }

    assert brings.all? { |edge| edge[:source] == "all-posts" }
    assert_equal ids(all), (brings.map { |edge| edge[:target] } - [ "more-all-posts" ]).sort
    assert_equal [ "more-all-posts" ], all[:more].map { |more| more[:id] }
    assert all[:more].first[:count].positive?
  end

  test "around a page nothing outside the viewer's scope is drawn: not the parent, not a child, not a post it lists" do
    tree
    list_block(@docs, content_type: "blog")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ @guide.id ] })
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })

    result = as(users(:author)) { local(page_focus(@guide, actor: users(:author)), depth: 2, actor: users(:author)) }

    assert_equal [ @guide, @intro ].map { |page| "page-#{page.id}" }, page_ids(result)
    assert_empty result[:nodes]
    assert_no_match(/page-#{@docs.id}\b/, result.to_json)
  end

  test "from a tag the walk steps along a lists line: the pages that list it are depth 1" do
    tree
    list_block(@blog, tag: "shared")

    result = local(tag_focus("shared"))

    assert_equal [ "page-#{@blog.id}" ], page_ids(result)
    assert_includes result[:edges], { source: "page-#{@blog.id}", target: "tag-#{Tag.find_by!(name: "shared").id}", kind: "lists" }
  end

  test "from a post, depth 2 reaches the pages that list one of its tags, and depth 1 does not" do
    tree
    list_block(@blog, tag: "shared")

    assert_empty page_ids(local(post_focus(@centre)))
    assert_equal [ "page-#{@blog.id}" ], page_ids(local(post_focus(@centre), depth: 2))
  end

  test "a page's local view costs the same with 3 listed posts and with 30: nine statements at depth 1, thirteen at depth 2" do
    tree
    list_block(@blog, tag: "many")
    3.times { |index| create_post(title: "Few #{index}", tags: [ "many" ]) }
    as(users(:two)) { Notes::Start.call(@blog, body: "A note") }
    viewer = users(:one)
    focus = page_focus(@blog, actor: viewer)
    count = ->(depth) { capture_sql { local(focus, depth: depth, actor: viewer) }.size }

    few = [ count.call(1), count.call(2) ]
    27.times { |index| create_post(title: "Many #{index}", tags: [ "many" ]) }

    # The walk around a page asks nothing. Depth 2: the site's five, the
    # relations among the posts drawn and the builder's seven. Depth 1: no
    # post is drawn, and a statement for no ids is not sent, so the relations
    # and the posts' notes, pending copies and rows are not asked for: the
    # site's five, the tags' names and the pages' three.
    assert_equal [ 9, 13 ], few
    assert_equal [ 9, 13 ], [ count.call(1), count.call(2) ]
  end

  # Payload note 4 of Task 3: a tag a readable page lists is a node whatever
  # carries it, so it is a focus too, and its local view is the page.
  test "a listed tag no readable post carries is a focus: its local view is the page that lists it, and the tag counts nothing" do
    tree
    Tag.create!(name: "empty")
    list_block(@blog, tag: "empty")

    result = local(tag_focus("empty"))

    assert_equal [ "page-#{@blog.id}" ], page_ids(result)
    assert_equal [ [ "empty", 0, 1 ] ], result[:tags].map { |tag| tag.values_at(:name, :count, :degree) }
    assert_empty result[:nodes]
  end

  # A node's state is `Publishing::State`'s in a local view as in the whole
  # graph (the builder's): the page's scheduled change with its time, a
  # listed draft as a draft.
  test "around a page every node carries Publishing::State's status and changes, and only a scheduled change its time" do
    tree
    list_block(@blog, content_type: "resume_entry")
    draft = create_post(title: "Draft", content_type: "resume_entry", published: false)
    live = create_post(title: "Live", content_type: "resume_entry")
    at = 2.days.from_now
    Publishing::Version.take!(@blog, live_at: at)
    @blog.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
    live.update_columns(unpublished_changes_at: Time.current)  # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)

    result = local(page_focus(@blog), depth: 2)
    page = result[:pages].find { |node| node[:id] == "page-#{@blog.id}" }
    posts = result[:nodes].index_by { |node| node[:id] }

    assert_equal [ "live", "scheduled" ], page.values_at(:status, :changes)
    assert_in_delta at.to_f, page[:change_at].to_f, 1
    assert_equal [ "draft", nil, nil ], posts[pid(draft)].values_at(:status, :changes, :change_at)
    assert_equal [ "live", "unpublished", nil ], posts[pid(live)].values_at(:status, :changes, :change_at)
    [ [ @blog, page ], [ draft, posts[pid(draft)] ], [ live, posts[pid(live)] ] ].each do |record, node|
      assert_equal Publishing::State.of(record.reload).status, node[:status]
    end
  end

  test "a page trashed after it was found as the focus is not found, not an error" do
    tree
    focus = page_focus(@blog)
    @blog.update_column(:trashed_at, Time.current)

    assert_raises(ActiveRecord::RecordNotFound) { local(focus, depth: 2) }
  end
end
