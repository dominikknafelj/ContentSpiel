require "test_helper"

# `Admin::NotesScreen::OpenThreadRowComponent`: one record with open threads in
# the Notes screen's rail, which is one link to the record's notes.
class Admin::NotesScreen::OpenThreadRowComponentTest < ViewComponent::TestCase
  setup do
    users(:two).update!(name: "Dana Weiss")
    users(:one).update!(name: "Jonas Lind")
    @page = create_page(title: "Pricing")
  end

  def rows(actor: users(:two)) = Dashboard::OpenThreads.new(actor: actor, channel: :admin, limit: 8, with_authors: true).rows

  test "a row is one link to the record's notes that does not prefetch, with its chip, title, count line and two avatars then +N" do
    first = as(users(:two)) { Notes::Start.call(@page, body: "First").record }
    as(users(:one)) { Notes::Reply.call(first, body: "Second") }
    as(users(:reader)) { Notes::Reply.call(first, body: "Third") }
    as(users(:two)) { Notes::Start.call(@page, body: "Another thread") }

    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadRowComponent.new(row: rows.sole) }

    assert_selector "a", count: 1
    assert_selector "a[href$='?notes=open'][data-turbo-frame='_top'][data-turbo-prefetch='false']"
    assert_selector "a > span[class~='size-5'][aria-hidden=true] svg"
    assert_selector "a .truncate.text-sm.text-ink", exact_text: "Pricing"
    assert_selector "a .text-meta", text: "2 notes · "
    assert_selector "a .text-meta time"
    assert_selector "a [aria-hidden=true].rounded-full", count: 3
    assert_selector "a span.rounded-full.size-\\[22px\\]", count: 3
    assert_selector "a span.bg-sunken", exact_text: "+1"
    assert_selector "a span.bg-people", exact_text: "DW"
  end

  test "an untitled record reads (untitled)" do
    as(users(:two)) { Notes::Start.call(@page, body: "Hello") }

    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadRowComponent.new(row: rows.sole.with(title: nil)) }

    assert_selector "a .truncate.text-sm.text-ink", exact_text: "(untitled)"
    assert_selector "a .text-meta", text: "1 note · "
  end
end
