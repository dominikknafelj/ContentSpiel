require "test_helper"

# `Admin::NotesScreen::OpenThreadsComponent`: the Notes screen's rail of
# records with open threads.
class Admin::NotesScreen::OpenThreadsComponentTest < ViewComponent::TestCase
  def threads(limit: 8) = Dashboard::OpenThreads.new(actor: users(:two), channel: :admin, limit: limit, with_authors: true)

  test "the rail is a section named by its heading, says how many more, and says No open threads. with none" do
    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadsComponent.new(threads: threads) }

    assert_selector "section.admin-list-rail__rail.admin-notes-threads[aria-labelledby=open-threads-heading] h2#open-threads-heading.text-h3", text: "Open threads"
    assert_selector "section > p.text-small.text-meta", text: "Unresolved notes on pages, posts and images"
    assert_selector "section .text-meta", text: "No open threads."
    assert_no_selector "ul"

    3.times { |index| as(users(:two)) { Notes::Start.call(create_page(title: "Page #{index}"), body: "Note") } }
    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadsComponent.new(threads: threads(limit: 2)) }

    assert_selector "section ul > li", count: 2
    assert_selector "section a", count: 2
    assert_selector "section .text-meta", text: "And 1 more on other pages"
    assert_no_text "No open threads."

    as(users(:two)) { render_inline Admin::NotesScreen::OpenThreadsComponent.new(threads: threads) }

    assert_selector "section ul > li", count: 3
    assert_no_text "more on other pages"
  end
end
