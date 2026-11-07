require "test_helper"

# `Admin::NotesScreen::InboxRowComponent`: one line of Notes for you, which is
# one link from its dot to its verb.
class Admin::NotesScreen::InboxRowComponentTest < ViewComponent::TestCase
  setup do
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    as(users(:two)) { assert Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]?").ok? }
  end

  test "the row ends in Open thread, under the time, inside its one link" do
    row = Dashboard::NotesForYou.new(actor: users(:reader), channel: :admin).rows.sole

    render_inline Admin::NotesScreen::InboxRowComponent.new(row:)

    assert_selector "a", count: 1
    assert_selector "a[data-delivery][class~='grid-cols-[7px_24px_1fr_auto]'] > span.admin-row-verb.col-start-4:last-child", exact_text: "Open thread"
    assert_selector "a [data-inbox-sentence]", text: "Dana mentioned you"
    assert_selector "a > span:nth-last-child(2) time"
  end
end
