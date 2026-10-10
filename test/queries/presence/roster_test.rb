require "test_helper"

# Who else is on a record, and which of these records have someone here
# (presence spec §5). Only fresh rows are read, whatever the sweep has
# deleted; the viewer is never in the answer; a person is there once.
class Presence::RosterTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @viewer = users(:two)
    @other = users(:one)
    @third = users(:reader)
    @roster = Presence::Roster.new(viewer: @viewer)
    @now = Time.zone.local(2026, 10, 10, 12, 0, 0)
  end

  def mark(user, record = @page, tab: "tab-#{user.id}-#{SecureRandom.hex(3)}", state: "here", seen: @now, arrived: seen)
    Presence::Mark.insert!({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, state:, seen_at: seen, arrived_at: arrived }) # version: none (a test of presence)
  end

  test "nobody else is nobody" do
    travel_to(@now) do
      mark(@viewer)
      assert_equal [], @roster.on(@page)
      assert_equal({}, @roster.here_counts([ @page ]))
    end
  end

  test "a row 61 seconds old is not seen and one 59 seconds old is" do
    travel_to(@now) do
      mark(@other, seen: @now - 61.seconds)
      mark(@third, seen: @now - 59.seconds)
      assert_equal [ @third ], @roster.on(@page).map(&:user)
      assert_equal({ @page.id => 1 }, @roster.here_counts([ @page ]))
    end
  end

  test "a person is one Person: here if any tab is here, with the earliest arrival" do
    travel_to(@now) do
      mark(@other, state: "away", arrived: @now - 10.minutes)
      mark(@other, state: "here", arrived: @now - 3.minutes)
      mark(@other, state: "here", arrived: @now - 5.minutes)
      people = @roster.on(@page)
      assert_equal 1, people.size
      assert_equal [ @other, "here", @now - 5.minutes ], people.first.deconstruct
    end
  end

  test "two away tabs are one Person, away, since the later seen_at" do
    travel_to(@now) do
      mark(@other, state: "away", seen: @now - 40.seconds)
      mark(@other, state: "away", seen: @now - 20.seconds)
      assert_equal [ [ @other, "away", @now - 20.seconds ] ], @roster.on(@page).map(&:deconstruct)
    end
  end

  test "here comes first, then the earliest arrival" do
    travel_to(@now) do
      a = User.create!(email_address: "a@example.com", password: "a-long-password-1")
      b = User.create!(email_address: "b@example.com", password: "a-long-password-1")
      mark(@other, state: "away", arrived: @now - 30.minutes)
      mark(@third, state: "here", arrived: @now - 2.minutes)
      mark(a, state: "here", arrived: @now - 9.minutes)
      mark(b, state: "away", arrived: @now - 40.minutes)
      assert_equal [ a, @third, b, @other ], @roster.on(@page).map(&:user)
    end
  end

  test "only the record asked for" do
    travel_to(@now) do
      other_page = create_page(title: "Other")
      mark(@other, other_page)
      assert_equal [], @roster.on(@page)
    end
  end

  test "the roster is two statements at most, at any number of people" do
    travel_to(@now) do
      assert_operator capture_sql { @roster.on(@page) }.size, :<=, 2
      2.times { |i| mark(User.create!(email_address: "p#{i}@example.com", password: "a-long-password-1")) }
      few = capture_sql { @roster.on(@page) }.size
      12.times { |i| mark(User.create!(email_address: "q#{i}@example.com", password: "a-long-password-1")) }
      many = capture_sql { assert_equal 14, @roster.on(@page).size }.size
      assert_operator few, :<=, 2
      assert_equal few, many
    end
  end

  test "here_counts counts users, not rows; leaves out away-only records and the viewer" do
    travel_to(@now) do
      busy = create_page(title: "Busy")
      quiet = create_page(title: "Quiet")
      mine = create_page(title: "Mine")
      mark(@other, busy)
      mark(@other, busy)
      mark(@third, busy)
      mark(@third, busy, state: "away")
      mark(@other, quiet, state: "away")
      mark(@viewer, mine)
      assert_equal({ busy.id => 2 }, @roster.here_counts([ busy, quiet, mine, @page ]))
      assert_equal({}, @roster.here_counts([]))
    end
  end

  test "here_counts is one statement for 3 records and for 30" do
    travel_to(@now) do
      pages = Array.new(30) { |i| create_page(title: "Page #{i}") }
      pages.each { |page| mark(@other, page) }
      assert_equal 1, capture_sql { @roster.here_counts(pages.first(3)) }.size
      assert_equal 1, capture_sql { assert_equal 30, @roster.here_counts(pages).size }.size
    end
  end

  test "here_counts for an image does not mix with a page of the same id" do
    travel_to(@now) do
      asset = create_media_asset
      Presence::Mark.insert!({ user_id: @other.id, record_type: "Media::Asset", record_id: @page.id, tab: "tab-xxxxxxxx", state: "here", seen_at: @now, arrived_at: @now }) # version: none (a test of presence)
      assert_equal({}, @roster.here_counts([ @page ]))
      assert_equal({ @page.id => 1 }, @roster.here_counts([ Media::Asset.new(id: @page.id) ]))
      assert_equal({}, @roster.here_counts([ asset ]))
    end
  end
end
