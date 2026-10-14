require "test_helper"

# `PostGraph::Kinds`: which kinds of node and of line a viewer may be shown,
# the one rule the legend's toggles follow (pages in the mind graph, spec §2
# and §6; the ruling on Task 6's review: a kind that can be drawn has its
# toggle and its key). Held against what the builder really answers, for
# each combination of rights, on a site where every kind the rights allow
# does occur.
class PostGraph::KindsTest < ActiveSupport::TestCase
  URL = ->(record) { "/#{record.class.name.underscore}/#{record.id}" }

  setup do
    blog = @blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    # A tag a page's list block names: a node for whoever reads the page,
    # whatever posts carry it (one does, so a reader of posts has its line).
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 1, settings: { "tag" => Tag.find_or_create_by!(name: "listed").name })
    a, b = 2.times.map { |index| create_post(title: "Post #{index}", tags: [ "shared", *("listed" if index.zero?) ]) }
    PostRelation.create!(post: a, related_post: b)
  end

  # What the answer holds, in the rule's own names: a `brings` line is how a
  # page lists (it follows "Lists", design answer H1).
  def drawn(answer)
    nodes = { page: answer[:pages], post: answer[:nodes], tag: answer[:tags], type: answer[:types] }.select { |_kind, held| held.present? }.keys
    lines = answer[:edges].map { |edge| edge[:kind] == "brings" ? :lists : edge[:kind].to_sym }.uniq
    { nodes: PostGraph::Kinds::NODES & nodes, lines: PostGraph::Kinds::LINES & lines }
  end

  def no_posts
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
  end

  def no_pages = access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })

  def answers(actor)
    as(actor) do
      whole = PostGraph::Global.call(actor: actor, url_for: URL, everything: true)
      # (A page the viewer cannot read is not found, and has no local view.)
      focus = begin
        PostGraph::Focus.find(actor: actor, page: @blog.id)
      rescue ActiveRecord::RecordNotFound
        nil
      end
      around = focus && PostGraph::Local.call(actor: actor, focus: focus, depth: 2, url_for: URL)
      [ whole, around ].compact
    end
  end

  test "someone who reads pages and posts may be shown every kind, and is" do
    author = users(:author)
    rule = PostGraph::Kinds.shown(pages: true, posts: true)

    assert_equal({ nodes: %i[page post tag type], lines: %i[tree lists related tag] }, rule)
    answers(author).each { |answer| assert_equal rule, drawn(answer) }
  end

  test "someone who reads posts and no page is shown posts, tags, related and shared tags, and nothing of pages" do
    no_pages
    rule = PostGraph::Kinds.shown(pages: false, posts: true)

    assert_equal({ nodes: %i[post tag], lines: %i[related tag] }, rule)
    assert_equal [ rule ], answers(users(:author)).map { |answer| drawn(answer) }, "the whole graph, and no page to stand around"
  end

  # The case the first rule missed: a tag a readable page's list block names
  # is a node whatever posts carry it, so a viewer of pages alone is shown a
  # tag, and gets its toggle.
  test "someone who reads pages and no post is shown pages, post types, the tree, lists and the tags their pages list" do
    no_posts
    rule = PostGraph::Kinds.shown(pages: true, posts: false)

    assert_equal({ nodes: %i[page tag type], lines: %i[tree lists] }, rule)
    whole, around = answers(users(:author))
    assert_equal rule, drawn(whole)
    assert_equal rule, drawn(around)
    assert_equal [ "listed" ], whole[:tags].map { |tag| tag[:name] }
  end

  test "someone who reads neither is shown nothing" do
    assert_equal({ nodes: [], lines: [] }, PostGraph::Kinds.shown(pages: false, posts: false))
  end

  test "every kind of the rule is one the data can hold, and the legend's toggles are the rule's" do
    assert_equal %i[page post tag type], PostGraph::Kinds::NODES
    assert_equal %i[tree lists related tag], PostGraph::Kinds::LINES
    assert_equal PostGraph::Kinds::NODES.sort, PostGraph::Kinds::NODE_NEEDS.keys.sort
    assert_equal PostGraph::Kinds::LINES.sort, PostGraph::Kinds::LINE_NEEDS.keys.sort
  end
end
