require "test_helper"

class Publishing::AddresslessTest < ActiveSupport::TestCase
  def listing_page(title)
    page = create_page(title: title, published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    page
  end

  def addressless?(record) = Publishing::Addressless.record?(record.reload)

  test "a live page with an address, the homepage, a draft and a scheduled page are not addressless" do
    live = create_page(title: "About")
    draft = create_page(title: "Draft", published: false)
    scheduled = create_page(title: "Later")
    scheduled.update_columns(published_at: 2.days.from_now) # version: none (a test schedules a page) # changes: none (a test schedules a page)

    assert_not addressless?(live)
    PublicPath.where(record: [ root_page, draft, scheduled ]).delete_all # version: none (a test takes addresses away) # changes: none (a test removes derived rows)
    assert_not addressless?(root_page), "the homepage has no slug to lose"
    assert_not addressless?(draft)
    assert_not addressless?(scheduled), "it is not live yet"
  end

  test "a live page whose address is gone is addressless, and a trashed one is not" do
    page = create_page(title: "Yielded")
    PublicPath.where(record: page).delete_all # version: none (a test takes an address away) # changes: none (a test removes derived rows)

    assert addressless?(page)
    assert Trash::Move.call(page).ok?
    assert_not addressless?(page)
  end

  test "a post that no page lists is not addressless: it was never going to have one" do
    post = create_post(title: "Nobody lists me")

    assert_nil PublicPath.current.find_by(record: post)
    assert_not addressless?(post)
  end

  test "a live post some list lists that has no address is addressless; the same post once it has one is not" do
    listing_page("Blog")
    post = create_post(title: "Listed")
    assert_not addressless?(post)

    PublicPath.where(record: post).delete_all # version: none (a test takes an address away) # changes: none (a test removes derived rows)

    assert addressless?(post)
  end

  # `test/integration/public_drafts_test.rb`: removing a page's list block and
  # publishing drops a live post to no address, because a subpage holds it.
  test "a live post that yielded its address to a subpage is addressless" do
    blog = listing_page("Blog")
    topic = listing_page("Topic")
    create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?
    publish_changes(blog)

    assert_nil PublicPath.current.find_by(record: post)
    assert addressless?(post), "topic still lists it, and the address /topic/hello is the subpage's"
  end
end
