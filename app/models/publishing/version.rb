# app/models/publishing/version.rb
module Publishing
  # One published copy of a page or post. Written once by `take!` and never
  # updated (`readonly?`); the only row ever removed is one whose `live_at`
  # is still in the future, replaced by the next `take!`.
  #
  # THE ORDER OF COPIES. `live_at` is never earlier than the moment a copy is
  # taken, and taking a copy removes the pending one, so there is at most one
  # copy in the future and ids, numbers and `live_at` all rise together.
  # `current` relies on that: the newest id among the copies in force is the
  # copy with the greatest `live_at` not after now.
  class Version < ApplicationRecord
    self.table_name = "published_versions"

    belongs_to :record, polymorphic: true
    belongs_to :created_by, class_name: "User", optional: true

    scope :of, ->(record) { where(record_type: record.class.polymorphic_name, record_id: record.id) }
    # Copies whose time has come.
    scope :in_force, ->(now = Time.current) { where(live_at: ..now) }
    # Copies waiting for their time: at most one per record.
    scope :pending, ->(now = Time.current) { where(arel_table[:live_at].gt(now)) }

    # The current copy of each record: the newest in force. `unscoped` on
    # purpose, so the choice of "newest" never depends on what else the
    # caller narrowed by (a `where(lists_posts: true)` must filter the
    # current copies, not pick the newest copy that lists posts).
    def self.current(now = Time.current)
      where(id: unscoped.in_force(now).group(:record_type, :record_id).select(arel_table[:id].maximum))
    end

    # Takes a copy of `record` from its rows. The caller holds the record's
    # row lock inside an open transaction (a save service after its `save`,
    # `Publishing::PublishChanges` after `lock`). `live_at` in the past means
    # now. A pending copy is replaced; its number is not given out again.
    def self.take!(record, live_at: nil, by: nil, now: Time.current)
      live_at = [ live_at || now, now ].max
      mine = of(record)
      number = (mine.maximum(:number) || 0) + 1
      mine.pending(now).delete_all
      data = Snapshot.of(record)
      version = create!(record_type: record.class.polymorphic_name, record_id: record.id, number: number, live_at: live_at,
        snapshot: data.except("blocks"), blocks: data.fetch("blocks", []), lists_posts: Snapshot.lists_posts?(data),
        tag_ids: data.fetch("tags", []).map { |tag| tag["id"] }.sort, created_by_id: by&.id, created_at: now)
      # A scheduled record shows nothing yet, so its copy changes nothing the
      # public can see (the moment it goes live is the content version's own
      # publication-time lookup, as for the record itself).
      PublicSite.bump_version! if record.live?
      version
    end

    # The first copy of every published or scheduled record that has none:
    # what the migration runs. Answers how many it took.
    def self.take_first_copies!
      [ Page, Post ].sum do |model|
        missing = model.where.not(published_at: nil).where.not(id: where(record_type: model.polymorphic_name).select(:record_id))
        missing.find_each.count { |record| transaction { take!(record) } }
      end
    end

    def readonly? = persisted?
  end
end
