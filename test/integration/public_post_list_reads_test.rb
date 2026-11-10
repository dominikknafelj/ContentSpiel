require "test_helper"

# What a post list costs a public page (#122): the same statements for 3
# posts as for 30, whatever the list's template draws. Its addresses are read
# in one statement (`PublicSite::Urls#prefetch`), its posts and their copies
# without their bodies (`Publishing::Listing.posts`), and a template that draws
# a body reads the list's bodies in at most two, here one: every post has a
# copy (`Publishing::DeferredBodies`).
class PublicPostListReadsTest < ActionDispatch::IntegrationTest
  setup { root_page }

  def path_of(record, locale = "en") = PublicSite::Urls.new.path_for(record, locale)

  # A published page listing `count` published posts of `type`, each with a
  # body of its own; the page and the posts are drawn from their copies. The
  # list is filtered by a tag of its own, so the two lists of a test do not
  # list each other's posts.
  def list_page(count, type:)
    tag = "list-#{count}"
    page = create_page(title: "#{type} #{count}")
    posts = Array.new(count) do |index|
      post = create_post(title: "#{type} #{count} #{index}", content_type: type, tags: [ tag ])
      Posts::Save.call(post, translations: { "en" => { body: rich_doc("Body #{index} #{"words " * 50}") } })
      publish_changes(post)
    end
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => type, "tag" => tag } })
    publish_changes(page)
    [ page, posts ]
  end

  # The statements of a second request for the page (the first warms what
  # every request reads once a process has started).
  def statements_for(page)
    get path_of(page)
    capture_sql { get path_of(page) }.tap { assert_response :success }
  end

  # A statement that reads a post's body: its rows whole or the body column,
  # or the body out of its copies (`Publishing::DeferredBodies`).
  def reads_a_body?(sql) = sql.include?('"posts".*') || sql.include?('"posts"."body"') || sql.include?("#> CAST('{fields,body}'")

  # The list's copies, read with the body taken out of their snapshot
  # (`Version.snapshot_without_field`).
  def copies_without_body(sql) = sql.count { |statement| statement.include?(Publishing::Version.snapshot_without_field("body").to_sql) }

  %w[blog resume_entry].each do |type|
    test "a #{type} list costs the same statements for 3 posts as for 30, and reads no body" do
      counts = [ 3, 30 ].map do |count|
        page, posts = list_page(count, type: type)
        sql = statements_for(page)

        assert_select ".content-block--post-list li a", count: count do |links|
          assert_equal posts.reverse.map { |post| path_of(post) }, links.map { |a| a["href"] }
        end
        assert_empty sql.select { |statement| reads_a_body?(statement) }
        assert_equal 1, copies_without_body(sql), sql.join("\n")
        sql
      end

      assert_equal counts.first.grep(/public_paths/).size, counts.last.grep(/public_paths/).size, "a post's address costs a statement of its own:\n#{counts.last.join("\n")}"
      assert_equal counts.first.size, counts.last.size, "a #{type} list's statements grow with its posts:\n#{counts.last.join("\n")}"
    end
  end

  test "the now list draws the latest post's published body, in the same statements for 3 posts as for 30" do
    counts = [ 3, 30 ].map do |count|
      page, = list_page(count, type: "now_update")
      sql = statements_for(page)

      assert_select ".content-block--post-list .cs-prose", text: /Body #{count - 1} words/
      assert_equal 1, copies_without_body(sql), sql.join("\n")
      assert_equal 1, sql.count { |statement| reads_a_body?(statement) }, sql.join("\n")
      sql.size
    end

    assert_equal counts.first, counts.last, "the now list's statements grow with its posts"
  end
end
