require "test_helper"

# `Admin::AuditScreen::TimeSpan` (final fix wave, M4/M4b): how the audit log
# writes WHEN. A plain module with no test of its own until a bug sat on it:
# `span?` compared the two ends as "HH:MM" STRINGS, so a span of exactly a day
# (or any whole number of days) read as a single moment.
class Admin::AuditScreen::TimeSpanTest < ActiveSupport::TestCase
  TimeSpan = Admin::AuditScreen::TimeSpan
  Row = Struct.new(:action, :occurred_at, :last_occurred_at, :occurrences)

  def row(first, last = first, occurrences: 1, action: "post.updated") = Row.new(action, first, last, occurrences)

  def in_berlin(&block) = Time.use_zone("Europe/Berlin", &block)

  test "one moment is one time; seconds apart within a minute is still one" do
    in_berlin do
      at = Time.utc(2026, 10, 2, 14, 5, 10)

      assert_not TimeSpan.span?(row(at))
      assert_not TimeSpan.span?(row(at, at + 40.seconds))
      assert_equal "16:05", TimeSpan.short(row(at, at + 40.seconds))
      assert_equal "Fri 2 Oct 2026, 16:05", TimeSpan.long(row(at))
    end
  end

  test "a span within a day shows both ends" do
    in_berlin do
      span = row(Time.utc(2026, 10, 2, 14, 5), Time.utc(2026, 10, 2, 14, 31))

      assert TimeSpan.span?(span)
      assert_equal "16:05–16:31", TimeSpan.short(span)
      assert_equal "Fri 2 Oct 2026, 16:05–16:31", TimeSpan.long(span)
    end
  end

  test "a span across midnight names the start's weekday, and both days in the long form" do
    in_berlin do
      span = row(Time.utc(2026, 10, 2, 21, 50), Time.utc(2026, 10, 2, 22, 10))

      assert_equal "Fri 23:50–00:10", TimeSpan.short(span)
      assert_equal "Fri 2 Oct 2026, 23:50 – Sat 3 Oct 2026, 00:10", TimeSpan.long(span)
    end
  end

  test "a span whose ends share a clock time on different days is still a span" do
    in_berlin do
      span = row(Time.utc(2026, 10, 2, 14, 5), Time.utc(2026, 10, 3, 14, 5))

      assert TimeSpan.span?(span)
      assert_equal "Fri 16:05–16:05", TimeSpan.short(span)
      assert_equal "Fri 2 Oct 2026, 16:05 – Sat 3 Oct 2026, 16:05", TimeSpan.long(span)
    end
  end

  test "a coalesced edit counts saves; anything else coalesced counts times; one occurrence says neither" do
    in_berlin do
      first, last = Time.utc(2026, 10, 2, 14, 5), Time.utc(2026, 10, 2, 14, 31)

      assert_equal "Fri 2 Oct 2026, 16:05–16:31 · 12 saves", TimeSpan.long(row(first, last, occurrences: 12))
      assert_equal "Fri 2 Oct 2026, 16:05–16:31 · 2 saves", TimeSpan.long(row(first, last, occurrences: 2, action: "block.updated"))
      assert_equal "Fri 2 Oct 2026, 16:05–16:31 · 12 times", TimeSpan.long(row(first, last, occurrences: 12, action: "access.denied"))
      assert_equal "Fri 2 Oct 2026, 16:05–16:31", TimeSpan.long(row(first, last, occurrences: 1))
      assert_equal "Fri 2 Oct 2026, 16:05–16:31", TimeSpan.long(row(first, last, occurrences: nil))
    end
  end
end
