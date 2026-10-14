require "test_helper"

# `PostGraph::Site`: what every view of the mind graph loads once.
class PostGraph::SiteTest < ActiveSupport::TestCase
  def limit_author_to(page)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ page.id ] })
  end

  test "it holds the readable posts, their tag links, the readable pages in tree order, and the listings" do
    blog = create_page(title: "Blog")
    child = create_page(title: "Child", parent: blog)
    first = create_page(title: "Made last, placed first")
    # Afterwards: creating a page renumbers its siblings.
    first.update_columns(position: 0) # version: none (a test sets a position) # changes: none (a test sets a position)
    blog.update_columns(position: 1)  # version: none (a test sets a position) # changes: none (a test sets a position)
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "tag" => "ruby" })
    post = create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    site = PostGraph::Site.load(actor: nil)

    assert_equal [ [ post.id, "blog" ] ], site.post_rows.map { |row| row.first(2) }
    assert_equal [ [ tag.id, post.id ] ], site.tag_links
    assert_equal({ tag.id => 1 }, site.tag_counts)
    assert_equal [ root_page.id, first.id, blog.id, child.id ], site.pages.map(&:id), "tree order, not the order of the ids"
    assert_equal root_page, site.home
    assert_equal blog.id, site.tree.parent(child.id)
    assert_equal [ [ blog.id, "tag-#{tag.id}" ] ], site.listings.edges
    assert_equal post.updated_at.to_i, site.stamps[post.id].to_i
    assert_nil site.page(0)
  end

  # Task 3's review, m2: the guard on `published_at` reads names, and a row
  # that carried the time as its third place could be compared with the
  # clock under any name a block parameter gave it. So the time never leaves
  # the one line that loads it: a row carries a NUMBER to order by.
  test "a post's publication time never leaves the site: a row carries its recency as a number, a draft's by when it was last changed" do
    live = create_post(title: "Live", published: true)
    draft = create_post(title: "Draft", published: false)
    live.update_columns(published_at: 3.days.ago) # version: none (a test sets a time) # changes: none (a test sets a time)

    rows = PostGraph::Site.load(actor: nil).post_rows.index_by(&:first)

    assert_equal [ live.reload.published_at.to_f, draft.reload.updated_at.to_f ], [ rows[live.id][2], rows[draft.id][2] ]
    assert_equal [ [ Integer, String, Float, ActiveSupport::TimeWithZone ] ], rows.values.map { |row| row.map(&:class) }.uniq
    assert_equal rows.values.sort_by(&:first), PostGraph::Site.rows_of(Post.where(id: [ live.id, draft.id ])).sort_by(&:first)
  end

  test "a trashed page, a trashed post and what is outside the viewer's scope are not in it" do
    kept = create_page(title: "Kept")
    hidden = create_page(title: "Hidden")
    gone = create_page(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    ContentBlock.create!(owner: hidden, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    create_post(title: "Binned").update_column(:trashed_at, Time.current)
    # The fixtures' author reads every post (`author_posts_read` has no
    # scope) and, from here on, the one page: so what is missing below is
    # missing for the page scope and for the trash, not for a posts scope.
    limit_author_to(kept)

    site = as(users(:author)) { PostGraph::Site.load(actor: users(:author)) }

    assert_equal [ kept.id ], site.pages.map(&:id)
    assert_nil site.home, "Home is outside the branch this viewer reads"
    assert_nil site.tree.parent(kept.id)
    assert_empty site.listings.edges, "a line of a page the viewer cannot read"
    assert_empty site.post_rows.map(&:first) & Post.trashed.pluck(:id)
  end

  # The posts half of the rule, by a viewer narrowed by POST rights (the
  # test above narrows by page and by the trash only): a post outside the
  # scope is in no row, no link, no count and no list, and a tag only it
  # carries has no count.
  test "a post outside the viewer's posts scope is in no row, no tag link, no count and no list of what a page lists" do
    %i[author_posts_read author_posts_create author_posts_edit].each { |grant| access_control_grants(grant).update!(scope: { "content_types" => [ "blog" ] }) }
    mine = create_post(title: "Mine", tags: [ "shared" ])
    theirs = create_post(title: "Theirs", content_type: "resume_entry", tags: [ "shared", "secret" ])
    page = create_page(title: "Lists")
    ContentBlock.create!(owner: page, block_type: :post_list, position: 0, settings: {})
    ContentBlock.create!(owner: page, block_type: :post_list, position: 1, settings: { "content_type" => "resume_entry" })
    shared, secret = %w[shared secret].map { |name| Tag.find_by!(name: name).id }

    site = as(users(:author)) { PostGraph::Site.load(actor: users(:author)) }
    whole = PostGraph::Site.load(actor: nil)

    assert_equal [ mine.id, theirs.id ], whole.post_rows.map(&:first).sort, "trusted code reads both: what follows is the scope's doing"
    assert_equal [ mine.id ], site.post_rows.map(&:first)
    assert_equal [ mine.id ], site.readable_posts.pluck(:id)
    assert_equal [ [ shared, mine.id ] ], site.tag_links
    assert_equal({ shared => 1 }, site.tag_counts)
    assert_not site.tag_counts.key?(secret)
    assert_equal [ mine.id ], site.stamps.keys
    assert_equal [ mine.id ], site.listings.posts_of(page.id)
    assert_equal [ 1, 0, 1, 1 ], [ site.listings.listed_count(page.id), site.listings.type_count("resume_entry"), site.listings.type_count("blog"), site.listings.post_count ]
    assert_not site.listings.listed?(theirs.id)
    assert_empty site.listings.unlisted
    assert_equal({ "all-posts" => 1 }, site.listings.left_out(page.id, shown: 0))
    assert_empty site.listings.left_out_of(page.id, "type-resume_entry", shown: 0)
    assert_nil site.listings.target_of(page.id, theirs.id)
  end

  test "it costs five statements, with 3 pages and posts and with 30" do
    viewer = users(:one)
    build = ->(count) do
      count.times do |index|
        page = create_page(title: "Page #{count}-#{index}")
        ContentBlock.create!(owner: page, block_type: :post_list, position: 0, settings: { "tag" => "ruby" })
        create_post(title: "Post #{count}-#{index}", tags: [ "ruby" ])
      end
    end

    build.call(3)
    few = capture_sql { PostGraph::Site.load(actor: viewer) }
    build.call(27)
    many = capture_sql { PostGraph::Site.load(actor: viewer) }

    assert_equal 5, few.size, few.join("\n")
    assert_equal 5, many.size, many.join("\n")
  end

  # A viewer who is no owner has grants to load (once per request) and, with
  # a branch scope, a narrower statement: the five and the grants, six, and the
  # same number at both sizes.
  test "for a viewer with a scope it costs the same with 3 pages and posts and with 30" do
    branch = create_page(title: "Branch")
    limit_author_to(branch)
    author = users(:author)
    build = ->(count) do
      count.times do |index|
        page = create_page(title: "Page #{count}-#{index}", parent: branch)
        ContentBlock.create!(owner: page, block_type: :post_list, position: 0, settings: { "tag" => "ruby" })
        create_post(title: "Post #{count}-#{index}", tags: [ "ruby" ])
      end
    end
    load = -> { Current.reset; as(author) { capture_sql { @site = PostGraph::Site.load(actor: author) } } }

    build.call(2)
    few = load.call
    assert_equal [ 3, 2 ], [ @site.pages.size, @site.post_rows.size ]
    build.call(27)
    many = load.call
    assert_equal [ 30, 29 ], [ @site.pages.size, @site.post_rows.size ]

    assert_equal few.size, many.size, many.join("\n")
    assert_equal 6, few.size, few.join("\n")
  end
end
