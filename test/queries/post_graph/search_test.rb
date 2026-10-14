require "test_helper"

class PostGraph::SearchTest < ActiveSupport::TestCase
  def search(text, actor: nil, limit: 10) = PostGraph::Search.call(actor: actor, text: text, limit: limit)

  test "posts by title and tags by name, posts first" do
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    create_post(title: "Unrelated", tags: [ "other" ])
    tag = Tag.find_by!(name: "ruby")

    assert_equal [ { kind: "post", id: "post-#{post.id}", record_id: post.id, label: "Ruby notes", colour_index: ContentTypes.fetch("blog").colour_index },
                   { kind: "tag", id: "tag-#{tag.id}", record_id: tag.id, label: "ruby" } ], search("rub")
  end

  test "pages come first, in tree order, each with its path; then posts with their type's colour; then tags" do
    docs = create_page(title: "Ruby docs")
    guide = create_page(title: "Ruby guide", parent: docs)
    early = create_page(title: "A Ruby page")
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    assert_equal [
      { kind: "page", id: "page-#{docs.id}", record_id: docs.id, label: "Ruby docs", path: "/ruby-docs" },
      { kind: "page", id: "page-#{guide.id}", record_id: guide.id, label: "Ruby guide", path: "/ruby-docs/ruby-guide" },
      { kind: "page", id: "page-#{early.id}", record_id: early.id, label: "A Ruby page", path: "/a-ruby-page" },
      { kind: "post", id: "post-#{post.id}", record_id: post.id, label: "Ruby notes", colour_index: ContentTypes.fetch("blog").colour_index },
      { kind: "tag", id: "tag-#{tag.id}", record_id: tag.id, label: "ruby" }
    ], search("ruby")
  end

  test "a post of a type that is no longer registered has no colour slot" do
    create_post(title: "Old talk").update_column(:content_type, "talk")

    assert_equal [ nil ], search("old talk").map { |row| row[:colour_index] }
  end

  test "at most `limit` pages, the first of the tree" do
    pages = 3.times.map { |index| create_page(title: "Many #{index}") }

    assert_equal pages.first(2).map { |page| "page-#{page.id}" }, search("many", limit: 2).select { |row| row[:kind] == "page" }.map { |row| row[:id] }
  end

  test "a page outside the viewer's scope and a trashed page are not listed" do
    seen = create_page(title: "Plan seen")
    create_page(title: "Plan hidden")
    create_page(title: "Plan gone").update_column(:trashed_at, Time.current)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    assert_equal [ "Plan seen" ], as(users(:author)) { search("plan", actor: users(:author)) }.select { |row| row[:kind] == "page" }.map { |row| row[:label] }
    assert_equal [ "Plan seen", "Plan hidden" ], search("plan").map { |row| row[:label] }
  end

  # A tag a readable page's list block names is a node of the graph and a
  # focus whatever carries it (`Focus`), so the search finds it too: by the
  # pages THIS viewer reads, and never one only a page they cannot read lists.
  test "a tag only a page lists is found by a viewer who reads that page, and by no other" do
    listing = create_page(title: "Listing")
    ContentBlock.create!(owner: listing, block_type: :post_list, position: 0, settings: { "tag" => "Orphaned" })
    tag = Tag.create!(name: "orphaned")
    Tag.create!(name: "orphan nobody names")

    assert_equal [ { kind: "tag", id: "tag-#{tag.id}", record_id: tag.id, label: "orphaned" } ], search("orphan"), "found whatever the case the block spells it in; a tag nothing names is not"
    assert_equal tag.id, PostGraph::Focus.find(actor: nil, tag: tag.id).id, "the row leads to a local view that is found"

    # (A grant on a page reaches the pages under it, so the other page is a sibling.)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ create_page(title: "Elsewhere").id ] })
    assert_empty as(users(:author)) { search("orphan", actor: users(:author)) }
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ listing.id ] })
    assert_equal [ "orphaned" ], as(users(:author)) { search("orphan", actor: users(:author)) }.map { |row| row[:label] }
  end

  # Two sizes far apart, varying everything a statement per row could hide
  # behind: pages (with children), posts, tags, and list blocks that name tags.
  test "it costs six statements whatever the number of pages, posts, tags and list blocks, and loads no page and no post whole" do
    grow = ->(from, upto) do
      (from...upto).each do |index|
        page = create_page(title: "Count #{index}")
        create_page(title: "Count child #{index}", parent: page)
        ContentBlock.create!(owner: page, block_type: :post_list, position: 0, settings: { "tag" => "count-listed-#{index}" })
        Tag.create!(name: "count-listed-#{index}")
        create_post(title: "Count post #{index}", tags: [ "count-#{index}" ])
      end
    end
    grow.call(0, 3)
    few = capture_sql { search("count") }
    grow.call(3, 30)
    many = capture_sql { search("count") }

    assert_equal [ 6, 6 ], [ few.size, many.size ], many.join("\n")
    assert_equal [ 10, 10, 10 ], %w[page post tag].map { |kind| search("count").count { |row| row[:kind] == kind } }
    assert many.none? { |sql| sql.include?('"pages".*') || sql.include?('"posts".*') }, "a whole row was loaded"
  end

  # For a page, a post and a tag alike (Task 7's review, M9: this test held
  # no page and no backslash, so a page search that stopped escaping would
  # not have been noticed here). A wildcard that was one would find every
  # row; a character finds only the row that has it.
  test "a typed %, _ or backslash is a character, not a wildcard, for a page, a post and a tag" do
    create_post(title: "Plain", tags: [ "plain" ])
    create_page(title: "Plain page")
    percent = create_page(title: "50% off")
    under = create_post(title: "snake_case", tags: [ "a_b" ])
    slash = create_post(title: "back\\slash")

    assert_equal [ "page-#{percent.id}" ], search("%").map { |row| row[:id] }
    assert_equal [ "post-#{under.id}", "tag-#{Tag.find_by!(name: 'a_b').id}" ], search("_").map { |row| row[:id] }
    assert_equal [ "post-#{slash.id}" ], search("\\").map { |row| row[:id] }
    assert_empty search("%_")
  end

  test "an unreadable or trashed post is not listed, nor a tag only such posts carry" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Secret plan", tags: [ "secret" ])
    gone = create_post(title: "Secret bin", tags: [ "secretbin" ])
    gone.update_column(:trashed_at, Time.current)

    assert_empty as(users(:author)) { search("secret", actor: users(:author)) }
    assert_equal [ "Secret plan", "secret" ], search("secret").map { |row| row[:label] }
  end

  test "at most `limit` of each" do
    3.times { |i| create_post(title: "Many #{i}", tags: [ "many#{i}" ]) }

    rows = search("many", limit: 2)

    assert_equal 2, rows.count { |row| row[:kind] == "post" }
    assert_equal 2, rows.count { |row| row[:kind] == "tag" }
  end

  test "posts are loaded with only the id, the title and the type" do
    create_post(title: "Ruby notes", tags: [ "ruby" ])

    statements = capture_sql { search("rub") }

    assert statements.any? { |sql| sql.include?('"posts"."id", "posts"."title", "posts"."content_type"') }, "the posts were not read:\n#{statements.join("\n")}"
    assert statements.none? { |sql| sql.include?('"posts".*') }, "a whole post row was loaded:\n#{statements.grep(/"posts"/).join("\n")}"
  end

  test "blank text finds nothing" do
    create_post(title: "A")

    assert_empty search("  ")
  end

  # The tree is one statement and the matching pages another. A page made,
  # restored or brought into the scope between the two is in the second and
  # not in the first: it is left out of this answer (it was not there a
  # moment ago), never a KeyError and a 500 for that keystroke.
  test "a page that appears between the tree's read and the matches' is left out of the answer, and nothing raises" do
    early = create_page(title: "Ruby early")
    late = create_page(title: "Ruby late")
    build = PostGraph::Tree.method(:new)

    result = with_singleton_override(PostGraph::Tree, :new, ->(rows) { build.call(rows.reject { |id, *| id == late.id }) }) { search("ruby") }

    assert_equal [ "page-#{early.id}" ], result.map { |row| row[:id] }
    assert_equal %w[Ruby\ early Ruby\ late], search("ruby").map { |row| row[:label] }, "and the next keystroke finds it"
  end
end
