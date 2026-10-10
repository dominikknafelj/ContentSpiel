module Presence
  # Who is on a record, and which of these records have someone here, for one
  # viewer. It reads only FRESH rows (`Mark.fresh`), so a person who left
  # without saying so is gone from every answer after 150 seconds
  # (`Presence::STALE_AFTER`) whatever the
  # sweep has deleted, and it never includes the viewer: your own other tab
  # is you, not company. It is told nothing about rights: the caller has
  # already found the record(s) through the read scope.
  class Roster
    # `since` is what "here for 12 minutes" and "away for 12 minutes" are
    # counted from:
    # - HERE: the earliest `arrived_at` among the person's fresh rows that are
    #   here (how long they have been on the record);
    # - AWAY: the LATEST `state_at` among their fresh rows that are away -- they
    #   have been away since the LAST of their tabs went away. A keep-alive
    #   moves `seen_at` and never `state_at`.
    Person = Data.define(:user, :state, :since)

    def initialize(viewer:)
      @viewer = viewer
    end

    # One Person per OTHER user with a fresh row on the record: here if any of
    # their fresh rows is, here before away, and within each by the EARLIEST
    # `arrived_at` over all their fresh rows, so a reload (a new tab, a new
    # row) does not send someone to the end. A user deleted since the rows
    # were read is skipped. Two statements at most, whatever the number of
    # people. It is told nothing about rights: the caller found the record
    # through the read scope.
    def on(record)
      rows = Mark.fresh.where(record_type: record.class.polymorphic_name, record_id: record.id).where.not(user_id: @viewer.id)
        .pluck(:user_id, :state, :arrived_at, :state_at)
      return [] if rows.empty?

      users = User.where(id: rows.map(&:first).uniq).index_by(&:id)
      rows.group_by(&:first).filter_map { |user_id, own| users[user_id] && [ person(users[user_id], own), own.map { |row| row[2] }.min ] }
        .sort_by { |person, arrived| [ person.state == "here" ? 0 : 1, arrived, person.user.id ] }
        .map(&:first)
    end

    # { record id => number of other users here } for the records of `kind`
    # (a `RecordKinds::Kind`) among `ids` -- an Array, or a relation selecting
    # ids, which becomes a subquery -- leaving out those with nobody here. One
    # statement and no record loaded, for any number of ids. Like `on`, it
    # trusts its caller to have narrowed `ids` through the read scope.
    def here_counts(kind, ids)
      Mark.fresh.where(record_type: kind.type, record_id: ids, state: "here")
        .where.not(user_id: @viewer.id).group(:record_id).distinct.count(:user_id)
    end

    private

    def person(user, rows)
      here = rows.select { |row| row[1] == "here" }
      return Person.new(user:, state: "here", since: here.map { |row| row[2] }.min) if here.any?

      Person.new(user:, state: "away", since: rows.map { |row| row[3] }.max)
    end
  end
end
