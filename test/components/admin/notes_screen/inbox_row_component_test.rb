require "test_helper"

# `Admin::NotesScreen::InboxRowComponent`: one line of Notes for you, which is
# one link from its avatar to its verb.
class Admin::NotesScreen::InboxRowComponentTest < ViewComponent::TestCase
  setup do
    users(:two).update!(name: "Dana")
    @pricing = @page = create_page(title: "Pricing")
    as(users(:two)) { assert Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]?").ok? }
  end

  test "the row ends in Open thread, under the time, inside its one link" do
    row = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole

    render_inline Admin::NotesScreen::InboxRowComponent.new(row:)

    assert_selector "a", count: 1
    assert_selector "a[data-delivery][class~='grid-cols-[26px_1fr_auto]'] > span.admin-row-verb.col-start-3:last-child", exact_text: "Open thread"
    assert_selector "a [data-inbox-sentence]", text: "Dana mentioned you"
    assert_selector "a > span:nth-last-child(2) time"
  end

  test "an unread row has the New chip and no dot or hidden Unread; a read row's sentence is dim" do
    row = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole

    render_inline Admin::NotesScreen::InboxRowComponent.new(row:)

    assert_selector "a > span [data-inbox-new][class~='bg-accent-tint'][class~='rounded-pill'][class~='text-accent']", exact_text: "New"
    assert_selector "[data-inbox-new] > span.bg-accent.size-1\\.5[aria-hidden=true]"
    assert_selector "[data-inbox-sentence][class~='text-ink'][class~='text-sm'] strong.font-semibold"
    assert_no_selector ".sr-only"
    assert_no_selector "a > span.size-\\[7px\\]"

    as(users(:reader)) { Notes::MarkRead.call }
    read = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole
    render_inline Admin::NotesScreen::InboxRowComponent.new(row: read)

    assert_no_selector "[data-inbox-new]"
    assert_selector "[data-inbox-sentence][class~='text-dim'] strong.font-medium"
    assert_selector "a:not([data-unread])"
  end

  test "the where line leads with the record's chip, and a block's type chip for a note on a block" do
    row = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole
    render_inline Admin::NotesScreen::InboxRowComponent.new(row:)

    assert_selector "[data-inbox-where] > span[class~='size-5'][class~='bg-ic-structure-bg'][aria-hidden=true] svg"
    assert_selector "[data-inbox-where] > span.truncate[class~='text-dim']", text: "Page · Pricing"

    block = @pricing.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { assert Notes::Start.call(block, body: "This one, @[#{users(:reader).id}]").ok? }
    on_block = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.find(&:block)
    render_inline Admin::NotesScreen::InboxRowComponent.new(row: on_block)

    assert_selector "[data-inbox-where] > span[data-block-icon=pilcrow][class~='size-5'][class~='bg-ic-text-bg']"
    assert_no_selector "[data-inbox-where] > span[class~='bg-ic-structure-bg']"
  end

  test "a post's chip is the lists hue and an image's the media hue" do
    post_record = create_post(title: "Hello")
    asset = create_media_asset
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:read_only), permission: "media.upload") { |grant| grant.scope = {} }
    [ post_record, asset ].each { |record| as(users(:two)) { assert Notes::Start.call(record, body: "For @[#{users(:reader).id}]").ok? } }
    rows = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.index_by(&:kind)

    render_inline Admin::NotesScreen::InboxRowComponent.new(row: rows.fetch("post"))
    assert_selector "[data-inbox-where] > span[class~='bg-ic-lists-bg']"
    render_inline Admin::NotesScreen::InboxRowComponent.new(row: rows.fetch("media"))
    assert_selector "[data-inbox-where] > span[class~='bg-ic-media-bg']"
  end

  test "someone with no name is the sunken circle with a message icon, 26px" do
    row = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole.with(by: nil, by_id: nil)

    render_inline Admin::NotesScreen::InboxRowComponent.new(row:)

    assert_selector "a > span[class~='size-[26px]'][class~='bg-sunken'][aria-hidden=true] svg"
  end
end
