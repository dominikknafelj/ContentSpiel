module Presence
  # Who is on a record, and which of these records have someone here, for one
  # viewer. It reads only FRESH rows (`Mark.fresh`), so a person who left
  # without saying so is gone from every answer after a minute whatever the
  # sweep has deleted, and it never includes the viewer: your own other tab
  # is you, not company. It is told nothing about rights: the caller has
  # already found the record(s) through the read scope.
  class Roster
    # `since`: for someone here, when their first tab arrived; for someone
    # away, when they were last seen.
    Person = Data.define(:user, :state, :since)

    def initialize(viewer:)
      @viewer = viewer
    end

    # One Person per OTHER user with a fresh row on the record: here if any of
    # their fresh rows is, here before away, then by arrival. Two statements
    # at most, whatever the number of people.
    def on(record)
      rows = Mark.fresh.where(record_type: record.class.polymorphic_name, record_id: record.id).where.not(user_id: @viewer.id)
        .pluck(:user_id, :state, :arrived_at, :seen_at)
      return [] if rows.empty?

      users = User.where(id: rows.map(&:first).uniq).index_by(&:id)
      rows.group_by(&:first).map { |user_id, own| [ person(users[user_id], own), own.map { |row| row[2] }.min ] }
        .sort_by { |person, arrived| [ person.state == "here" ? 0 : 1, arrived, person.user.id ] }
        .map(&:first)
    end

    # { record id => number of other users here } for records of ONE type,
    # leaving out those with nobody here. One statement for any number of
    # records.
    def here_counts(records)
      return {} if records.empty?

      Mark.fresh.where(record_type: records.first.class.polymorphic_name, record_id: records.map(&:id), state: "here")
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
