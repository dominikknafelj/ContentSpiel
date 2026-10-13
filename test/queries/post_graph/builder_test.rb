require "test_helper"

# `PostGraph::Builder` (pages in the mind graph, spec §1, §4): `plan` says
# which lines a response holds and asks the database nothing; `build` makes
# the nodes. What only a page's local view hands it (the `brings` lines and
# the "+N more" pills) is tested here, with the views that do not ask yet.
class PostGraph::BuilderTest < ActiveSupport::TestCase
  def builder(site = PostGraph::Site.load(actor: nil), **options)
    PostGraph::Builder.new(site: site, locale: Locales.default, url_for: ->(record) { "/#{record.class.name.underscore}/#{record.id}" }, **options)
  end

  def pid(post) = "post-#{post.id}"
  def page_id(page) = "page-#{page.id}"

  def list_block(page, **settings)
    ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: settings.stringify_keys)
  end

  setup do
    @home = root_page
    @blog = create_page(title: "Blog")
    list_block(@blog, content_type: "blog")
    list_block(@blog, tag: "ruby")
    @a = create_post(title: "A", tags: [ "ruby" ])
    @b = create_post(title: "B")
    PostRelation.create!(post: @a, related_post: @b)
    @ruby = Tag.find_by!(name: "ruby")
    @site = PostGraph::Site.load(actor: nil)
  end

  def whole_plan(builder, **options)
    builder.plan(post_ids: [ @a.id, @b.id ], relations: [ [ @a.id, @b.id ] ], tag_links: @site.tag_links, tag_counts: @site.tag_counts,
                 min_tag_edges: 2, page_ids: @site.pages.map(&:id), lists: @site.listings.edges, **options)
  end

  test "a plan names every line of the response and asks the database nothing, and building it costs seven statements" do
    as(users(:two)) { Notes::Start.call(@a, body: "A note"); Notes::Start.call(@blog, body: "A note") }
    builder = builder(@site)

    planning = capture_sql { @plan = whole_plan(builder) }
    building = capture_sql { @graph = builder.build(@plan) }

    assert_empty planning
    assert_equal 7, building.size, building.join("\n")
    assert_equal [ { source: pid(@a), target: pid(@b), kind: "related" }, { source: pid(@a), target: "tag-#{@ruby.id}", kind: "tag" },
                   { source: page_id(@blog), target: page_id(@home), kind: "tree" },
                   { source: page_id(@blog), target: "type-blog", kind: "lists" }, { source: page_id(@blog), target: "tag-#{@ruby.id}", kind: "lists" } ], @plan.edges
    assert_equal @plan.edges, @graph[:edges]
    assert_not @graph.key?(:more), "no pill, no key"
  end

  # Third and fourth design answers (H1): in a page's local view the hub
  # that brings a post in draws a line to it, and each target that brings in
  # more than is drawn has a pill of its own, hanging off it the same way.
  test "a brings line joins a hub to its post and to its pill, one pill per target, and each end's degree counts it" do
    builder = builder(@site)
    more = [ { page_id: @blog.id, target: "type-blog", count: 92 }, { page_id: @blog.id, target: "tag-#{@ruby.id}", count: 3 } ]

    graph = builder.build(whole_plan(builder, brought: [ [ "type-blog", @b.id ] ], more: more))
    brings = graph[:edges].select { |edge| edge[:kind] == "brings" }

    assert_equal [ { source: "type-blog", target: pid(@b), kind: "brings" }, { source: "type-blog", target: "more-type-blog", kind: "brings" },
                   { source: "tag-#{@ruby.id}", target: "more-tag-#{@ruby.id}", kind: "brings" } ], brings
    assert_equal [ { id: "more-type-blog", count: 92, page: page_id(@blog), target: "type-blog" },
                   { id: "more-tag-#{@ruby.id}", count: 3, page: page_id(@blog), target: "tag-#{@ruby.id}" } ], graph[:more]
    assert_equal 3, graph[:types].first[:degree], "its lists line, its post and its pill"
    assert_equal 3, graph[:tags].first[:degree], "its post, its lists line and its pill"
    post = graph[:nodes].find { |node| node[:id] == pid(@b) }
    assert_equal [ 2, 1, 0 ], post.values_at(:degree, :related_count, :tag_count), "a brings line is neither half of the card's two numbers"
  end

  test "a tag deleted after the plan was made is no node, and its lines and its pill are gone with it" do
    builder = builder(@site)
    plan = whole_plan(builder, more: [ { page_id: @blog.id, target: "tag-#{@ruby.id}", count: 3 }, { page_id: @blog.id, target: "type-blog", count: 1 } ])
    PostTag.where(tag_id: @ruby.id).delete_all
    @ruby.delete

    graph = builder.build(plan)

    assert_empty graph[:tags]
    assert_no_match(/tag-#{@ruby.id}\b/, graph.to_json)
    assert_equal [ "more-type-blog" ], graph[:more].map { |pill| pill[:id] }
    assert_equal [ 1, 0 ], graph[:nodes].find { |node| node[:id] == pid(@a) }.values_at(:degree, :tag_count)
    assert_equal 2, graph[:pages].find { |node| node[:id] == page_id(@blog) }[:degree], "its tree line and its line to the type"
  end

  # The builder is told the time once, and judges every node and every
  # pending copy by it: a copy pending now is in force the day after.
  test "the state and the pending copies are judged at the time the builder is given" do
    [ @blog, @a ].each do |record|
      Publishing::Version.take!(record, live_at: 2.days.from_now)
      record.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
    end
    site = PostGraph::Site.load(actor: nil)
    looks = ->(graph) { [ graph[:pages].find { |node| node[:id] == page_id(@blog) }, graph[:nodes].find { |node| node[:id] == pid(@a) } ].map { |node| node.values_at(:changes, :change_at).then { |changes, at| [ changes, at.present? ] } } }

    today = builder(site)
    later = builder(site, now: 3.days.from_now)

    assert_equal [ [ "scheduled", true ], [ "scheduled", true ] ], looks.call(today.build(whole_plan(today)))
    assert_equal [ [ "unpublished", false ], [ "unpublished", false ] ], looks.call(later.build(whole_plan(later)))
  end

  test "post_nodes answers a node for each id with no line counted, in three statements" do
    builder = builder(@site)
    as(users(:two)) { Notes::Start.call(@a, body: "A note") }

    statements = capture_sql { @nodes = builder.post_nodes([ @b.id, @a.id ]) }

    assert_equal 3, statements.size, statements.join("\n")
    assert_equal [ pid(@a), pid(@b) ], @nodes.map { |node| node[:id] }
    assert_equal [ [ 0, 0, 0, 1, true ], [ 0, 0, 0, 0, true ] ], @nodes.map { |node| node.values_at(:degree, :related_count, :tag_count, :open_notes, :listed) }
  end
end
