require "test_helper"

class Notes::ListingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @right = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 2, position: 0)
    @left = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    @last = @page.content_blocks.create!(block_type: "rich_text", position: 1)
  end

  def note(subject, body = "A note") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  test "groups: the record first, then the blocks in the page's display order; pinned and resolved apart" do
    on_last, on_right, on_left, on_page = [ @last, @right, @left, @page ].map { |subject| note(subject) }
    pinned = note(@left, "Ask Dana first")
    done = note(@page, "Done")
    as(users(:two)) { Notes::Pin.call(pinned); Notes::Resolve.call(done) }

    listing = Notes::Listing.new(@page.reload)

    assert_equal [ pinned ], listing.pinned
    assert_equal [ @page, @left, @right, @last ], listing.groups.map(&:subject)
    assert_equal [ [ on_page ], [ on_left ], [ on_right ], [ on_last ] ], listing.groups.map(&:threads)
    assert_equal "ContentBlock-#{@left.id}", listing.groups.second.key
    assert_equal [ 5, 1 ], [ listing.open_count, listing.resolved_count ]
    assert_equal [ done ], listing.resolved
    assert_equal @left, listing.subject_of(pinned)
  end

  test "the newest thread of a group comes first" do
    old = note(@page, "Old")
    recent = travel_to(1.minute.from_now) { note(@page, "New") }
    travel_to(2.minutes.from_now) { as(users(:reader)) { Notes::Reply.call(old, body: "Bumped") } }

    assert_equal [ old, recent ], Notes::Listing.new(@page).groups.first.threads
  end

  test "it lists 50 and knows there are more; the counts stay exact" do
    as(users(:two)) { 51.times { |index| Notes::Start.call(@page, body: "Note #{index}") } }
    listing = Notes::Listing.new(@page)

    assert_equal [ 50, 51, true, 100 ], [ listing.groups.sum { |group| group.threads.size }, listing.open_count, listing.more?, listing.next_limit ]
    assert_equal 51, Notes::Listing.new(@page, limit: 100).groups.first.threads.size
    assert_equal 50, Notes::Listing.new(@page, limit: "junk").groups.first.threads.size
  end

  test "it costs the same statements with two threads as with twelve" do
    read = lambda do
      capture_sql do
        listing = Notes::Listing.new(Page.find(@page.id))
        listing.pinned
        listing.groups.each { |group| group.threads.each { |thread| thread.messages.each(&:body) } }
        [ listing.open_count, listing.resolved_count, listing.users, listing.following?(Notes::Thread.first, users(:two)), listing.unread?(Notes::Thread.first, users(:two)) ]
      end.size
    end
    2.times { note(@left) }
    few = read.call
    10.times { |index| as(users(:reader)) { Notes::Reply.call(note([ @page, @right, @last ][index % 3]), body: "Hi @[#{users(:two).id}]") } }

    assert_equal few, read.call
  end

  test "find is among this container's threads only" do
    mine = note(@page)
    elsewhere = note(create_page(title: "Other"))
    listing = Notes::Listing.new(@page)

    assert_equal mine, listing.find(mine.id)
    assert_nil listing.find(elsewhere.id)
  end
end
