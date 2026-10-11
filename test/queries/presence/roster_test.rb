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
    @page_kind = RecordKinds.named("page")
  end

  def mark(user, record = @page, tab: "tab-#{user.id}-#{SecureRandom.hex(3)}", state: "here", seen: @now, arrived: seen, state_at: arrived)
    Presence::Mark.insert!({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, token: SecureRandom.hex(8), state:, seen_at: seen, arrived_at: arrived, state_at: }) # version: none (a test of presence)
  end

  def counts(records, kind: @page_kind) = @roster.here_people(kind, records.map(&:id)).transform_values(&:count)

  test "nobody else is nobody" do
    travel_to(@now) do
      mark(@viewer)
      assert_equal [], @roster.on(@page)
      assert_equal({}, counts([ @page ]))
    end
  end

  test "a row just past STALE_AFTER is not seen and one just inside it is" do
    travel_to(@now) do
      mark(@other, seen: @now - 151.seconds)
      mark(@third, seen: @now - 149.seconds)
      assert_equal [ @third ], @roster.on(@page).map(&:user)
      assert_equal({ @page.id => 1 }, counts([ @page ]))
    end
  end

  test "a person is one Person: here if any tab is here, since their earliest arrival among the tabs that are here" do
    travel_to(@now) do
      mark(@other, state: "away", arrived: @now - 10.minutes)
      mark(@other, state: "here", arrived: @now - 3.minutes)
      mark(@other, state: "here", arrived: @now - 5.minutes)
      people = @roster.on(@page)
      assert_equal 1, people.size
      assert_equal [ @other, "here", @now - 5.minutes ], people.first.deconstruct
    end
  end

  test "an away person is away since the LAST of their tabs went away, however often the tabs beat" do
    travel_to(@now) do
      mark(@other, state: "away", seen: @now - 5.seconds, arrived: @now - 30.minutes, state_at: @now - 20.minutes)
      mark(@other, state: "away", seen: @now - 9.seconds, arrived: @now - 25.minutes, state_at: @now - 12.minutes)
      assert_equal [ [ @other, "away", @now - 12.minutes ] ], @roster.on(@page).map(&:deconstruct)
    end
  end

  test "a stale here row does not make a person here, nor give them an away time" do
    travel_to(@now) do
      mark(@other, state: "here", seen: @now - 151.seconds)
      mark(@other, state: "away", seen: @now - 10.seconds, state_at: @now - 8.minutes)
      assert_equal [ [ @other, "away", @now - 8.minutes ] ], @roster.on(@page).map(&:deconstruct)
    end
  end

  test "here comes first, then the earliest arrival of any of the person's tabs, so a reload keeps their place" do
    travel_to(@now) do
      a = User.create!(email_address: "a@example.com", password: "a-long-password-1")
      b = User.create!(email_address: "b@example.com", password: "a-long-password-1")
      mark(@other, state: "away", arrived: @now - 30.minutes)
      mark(@third, state: "here", arrived: @now - 2.minutes)
      mark(a, state: "here", arrived: @now - 9.minutes)
      mark(b, state: "away", arrived: @now - 40.minutes)
      assert_equal [ a, @third, b, @other ], @roster.on(@page).map(&:user)

      # `@third` reloads: a new tab, here since a minute ago, but their older tab came 20 minutes ago.
      mark(@third, state: "here", arrived: @now - 20.minutes)
      mark(@third, state: "here", arrived: @now - 1.minute)
      assert_equal [ @third, a ], @roster.on(@page).first(2).map(&:user)
    end
  end

  test "only the record asked for" do
    travel_to(@now) do
      mark(@other, create_page(title: "Other"))
      assert_equal [], @roster.on(@page)
    end
  end

  test "a user deleted between the two statements is skipped, not an error" do
    travel_to(@now) do
      mark(@other)
      mark(@third)
      roster = @roster
      deleted = false
      callback = lambda do |*, payload|
        next if deleted || !payload[:sql].include?("FROM \"presence_marks\"")

        deleted = true
        Presence::Mark.where(user_id: @third.id).delete_all # version: none (a test of presence)
        User.where(id: @third.id).delete_all # version: none (a test of a user going between two statements)
      end
      people = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { roster.on(@page) }
      assert_equal [ @other ], people.map(&:user)
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

  # --- here_people: who is here on each of a list's records ------------------

  def people(records, kind: @page_kind) = @roster.here_people(kind, records.map(&:id))

  test "here_people names the users here on each record in order of arrival, once each, without the viewer, the away and the stale" do
    travel_to(@now) do
      busy = create_page(title: "Busy")
      quiet = create_page(title: "Quiet")
      mine = create_page(title: "Mine")
      stale = create_page(title: "Stale")
      mark(@third, busy, arrived: @now - 10.minutes)
      mark(@other, busy, arrived: @now - 5.minutes)
      mark(@other, busy, arrived: @now - 1.minute)
      mark(@other, quiet, state: "away")
      mark(@viewer, mine)
      mark(@viewer, busy)
      mark(@other, stale, seen: @now - 151.seconds)

      answer = people([ busy, quiet, mine, stale, @page ])

      assert_equal [ busy.id ], answer.keys
      assert_equal 2, answer[busy.id].count
      assert_equal [ @third, @other ], answer[busy.id].users
      assert_equal({}, people([]))
    end
  end

  test "here_people keeps a person's place across a reload: the earliest arrival of all their fresh rows, here or away" do
    travel_to(@now) do
      mark(@other, arrived: @now - 20.minutes, state: "away")
      mark(@other, arrived: @now - 1.minute)
      mark(@third, arrived: @now - 10.minutes)

      assert_equal [ @other, @third ], people([ @page ])[@page.id].users
    end
  end

  test "here_people counts everyone and loads the first five" do
    travel_to(@now) do
      seven = Array.new(7) { |i| User.create!(name: "Person #{i}", email_address: "person#{i}@example.com", password: "a-long-password-1") }
      seven.each_with_index { |user, index| mark(user, arrived: @now - (20 - index).minutes) }

      here = people([ @page ])[@page.id]

      assert_equal 7, here.count
      assert_equal seven.first(5), here.users
      assert_equal 5, Presence::Roster::NAMED
    end
  end

  test "here_people is one statement for the marks and one for the users, for 3 records and for 30, and none for the users with nobody here" do
    travel_to(@now) do
      pages = Array.new(30) { |i| create_page(title: "Page #{i}") }
      pages.each { |page| mark(@other, page) && mark(@third, page) }
      assert_equal 2, capture_sql { assert_equal 3, people(pages.first(3)).size }.size
      statements = capture_sql { assert_equal 30, people(pages).size }
      assert_equal 2, statements.size
      assert_equal 1, capture_sql { assert_equal({}, people([ @page ])) }.size
      # A relation is a subquery of the one statement, and no record is loaded.
      relation = Page.where(id: pages.first(5).map(&:id)).select(:id)
      statements = capture_sql { assert_equal 5, @roster.here_people(@page_kind, relation).size }
      assert_equal 2, statements.size
      assert statements.none? { |statement| statement.include?("SELECT \"pages\".* ") }
    end
  end

  test "here_people counts users, not rows" do
    travel_to(@now) do
      mark(@other)
      mark(@other)
      mark(@third)
      mark(@third, state: "away")
      assert_equal({ @page.id => 2 }, counts([ @page ]))
    end
  end

  # Names are read from three columns; a password digest has no business in
  # the rows a marker is worded from.
  test "here_people loads only what a name is made of" do
    travel_to(@now) do
      mark(@other)
      statements = capture_sql { people([ @page ]) }
      assert_match(/SELECT "users"\."id", "users"\."name", "users"\."email_address" FROM "users"/, statements.last)
      assert_no_match(/password/, statements.last)
    end
  end

  # A user deleted between the two statements: the foreign key's cascade
  # takes their marks with them, so the state cannot be made in the tables;
  # the second statement is answered here as if they had just gone. Nobody
  # is counted who cannot be named: no " is here" without a name, no wrong
  # "and N more".
  test "here_people neither counts nor names a user who is gone by the second statement" do
    travel_to(@now) do
      alone = create_page(title: "Alone")
      mark(@other, arrived: @now - 5.minutes)
      mark(@third, arrived: @now - 1.minute)
      mark(@other, alone)
      seven = Array.new(7) { |i| User.create!(name: "Person #{i}", email_address: "person#{i}@example.com", password: "a-long-password-1") }
      crowd = create_page(title: "Crowd")
      seven.each_with_index { |user, index| mark(user, crowd, arrived: @now - (20 - index).minutes) }

      remaining = User.where.not(id: [ @other.id, seven.first.id ])
      answer = with_singleton_override(User, :where, ->(*) { remaining }) { people([ @page, alone, crowd ]) }

      assert_equal [ crowd.id, @page.id ].sort, answer.keys.sort
      assert_equal 1, answer[@page.id].count
      assert_equal [ @third ], answer[@page.id].users
      assert_equal 6, answer[crowd.id].count
      assert_equal seven[1..4], answer[crowd.id].users
    end
  end

  test "here_people for an image does not mix with a page of the same id" do
    travel_to(@now) do
      mark(@other, Media::Asset.new(id: @page.id))
      assert_equal({}, people([ @page ]))
      assert_equal [ @other ], people([ Media::Asset.new(id: @page.id) ], kind: RecordKinds.named("media"))[@page.id].users
    end
  end
end
