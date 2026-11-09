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
    assert_selector "a > span.flex.flex-none.items-center.gap-0\\.5", count: 1
    assert_no_selector "a [class*='-ml-'], a [class*='ring-2'], a[class*='avatar-ground']"
  end

  test "an untitled record reads (untitled)" do
    as(users(:two)) { Notes::Start.call(@page, body: "Hello") }

    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadRowComponent.new(row: rows.sole.with(title: nil)) }

    assert_selector "a .truncate.text-sm.text-ink", exact_text: "(untitled)"
    assert_selector "a .text-meta", text: "1 note · "
  end

  def writers_of(*people)
    thread = as(users(:two)) { Notes::Start.call(@page, body: "First").record }
    people.each_with_index do |person, index|
      Notes::Message.create!(thread: thread, author: person, body: "Reply #{index}", created_at: (index + 1).minutes.from_now)
    end
    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadRowComponent.new(row: rows.sole) }
    page.find("a .sr-only", visible: :all).text(:all)
  end

  test "the link's name keeps its visible words first and then names the writers: one, two, more than two, and one who is gone" do
    assert_equal ", by Dana Weiss", writers_of
    assert_selector "a > span > .truncate.text-small", text: /\A1 note · .*, by Dana Weiss\z/
    assert_selector "a [aria-hidden=true].rounded-full", count: 1
  end

  test "two writers read joined by and" do
    assert_equal ", by Jonas Lind and Dana Weiss", writers_of(users(:one))
  end

  test "more than two writers read as the newest two and how many more" do
    assert_equal ", by Dana Weiss, reader and 1 more", writers_of(users(:one), users(:reader), users(:two))
  end

  test "a writer who is gone reads a deleted user" do
    gone = User.create!(email_address: "gone-writer@example.com", password: "a-long-password-1")
    thread = as(users(:two)) { Notes::Start.call(@page, body: "First").record }
    Notes::Message.create!(thread: thread, author: gone, body: "Bye", created_at: 1.minute.from_now)
    Notes::Message.where(author_id: gone.id).update_all(author_id: nil) # version: none (a test's own setup: what the foreign key does when the author is deleted)

    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadRowComponent.new(row: rows.sole) }

    assert_selector "a span.rounded-full.border-field-line.bg-surface", exact_text: "", count: 1
    assert_selector "a span.bg-people", exact_text: "DW", count: 1
    assert_equal ", by a deleted user and Dana Weiss", page.find("a .sr-only", visible: :all).text(:all)
  end
end
