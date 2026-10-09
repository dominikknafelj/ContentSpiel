require "test_helper"

class Dashboard::OpenThreadsTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @quiet = create_post(title: "Quiet")
  end

  def note(subject) = as(users(:two)) { Notes::Start.call(subject, body: "A note") }.record

  def open_threads(user = users(:reader)) = Dashboard::OpenThreads.new(actor: user, channel: :admin)

  test "records with open threads, the most recently active first, with their counts" do
    note(@page)
    travel_to(1.minute.from_now) { note(@post) }
    travel_to(2.minutes.from_now) { note(@block) }
    as(users(:two)) { Notes::Resolve.call(note(@quiet)) }

    rows = open_threads.rows

    assert_equal [ [ @page, "page", "Pricing", 2 ], [ @post, "post", "Hello", 1 ] ], rows.map { |row| [ row.record, row.kind, row.title, row.count ] }
    assert_equal [ :admin_page_path, [ @page.id ], { notes: "open" } ], rows.first.route.then { |route| [ route.name, route.args, route.params ] }
    assert_equal 3, open_threads.total
  end

  test "an image's row leads to the Media screen with the image chosen, for someone who may open the library" do
    asset = create_media_asset
    note(asset)

    assert_empty open_threads.rows # Read only has no media.upload
    row = open_threads(users(:two)).rows.first
    assert_equal [ asset, "media", :admin_media_path, [], { selected: asset.id } ], [ row.record, row.kind, row.route.name, row.route.args, row.route.params ]
  end

  test "five rows, read-scoped, in a constant number of statements" do
    posts = Array.new(7) { |index| create_post(title: "Post #{index}") }
    posts.first(2).each { |post| note(post) }
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    open_threads.rows # warm-up: the fixture user's grants are read once and kept on the object
    few = capture_sql { open_threads.then { |query| [ query.rows, query.total ] } }.size
    posts.each { |post| note(post) }

    assert_equal 5, open_threads.rows.size
    assert_equal 9, open_threads.total
    assert_equal few, capture_sql { open_threads.then { |query| [ query.rows, query.total ] } }.size
    assert_equal [ [], 0 ], open_threads(stranger).then { |query| [ query.rows, query.total ] }
  end
end
