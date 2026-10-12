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

    # The copies of these records (a list of Page/Post, or unsaved stand-ins
    # with an id): the record condition is a part of THIS relation, so it can
    # be put inside a subquery as well.
    def self.among(records)
      records.group_by { |record| record.class.polymorphic_name }
        .map { |type, list| unscoped.where(record_type: type, record_id: list.map(&:id)) }
        .reduce(:or) || none
    end

    # `{ [record_type, record_id] => Version }`: the newest copy in force of
    # each record, in one statement whose subquery is narrowed to those
    # records (the index serves it) and whose answer does not depend on what
    # else a caller narrows by afterwards.
    def self.current_for(records, now: Time.current)
      newest = among(records).in_force(now).group(:record_type, :record_id).select(arel_table[:id].maximum)
      unscoped.where(id: newest).index_by { |version| [ version.record_type, version.record_id ] }
    end

    # The newest copy in force of EVERY record, whole table: for a sweep. A
    # record or a list asks `Publishing.current` / `current_for`.
    def self.current(now = Time.current)
      where(id: unscoped.in_force(now).group(:record_type, :record_id).select(arel_table[:id].maximum))
    end

    # Takes a copy of `record`, from its ROWS as they are at this moment: the
    # first statement locks the record's row (the page's row first, the same
    # first lock every block write takes, `ContentBlocks::Structure#lock_owner`;
    # a post's row, which `Posts::Save` already holds by its own UPDATE and
    # `Trash::Purge` takes after a post's destroy, never ahead of it) and the
    # fields, blocks and tags are read after it. The object in memory is not
    # read and not changed: a colleague's autosave committed since this
    # request loaded it is in the copy. The work is one transaction of its own
    # (it joins the caller's: a save service after its `save`,
    # `Publishing::PublishChanges`), so the lock, the removal of a pending copy
    # and the new copy stand or fall together, also for a caller with none.
    # `live_at` in the past means now. A pending copy is replaced; its number
    # is not given out again.
    def self.take!(record, live_at: nil, by: nil, now: Time.current)
      transaction do
        row = record.class.lock.find(record.id)
        live_at = [ live_at || now, now ].max
        mine = of(row)
        number = (mine.maximum(:number) || 0) + 1
        mine.pending(now).delete_all
        data = Snapshot.of(row, row: row)
        version = create!(record_type: row.class.polymorphic_name, record_id: row.id, number: number, live_at: live_at,
          snapshot: data.except("blocks"), blocks: data.fetch("blocks", []), lists_posts: Snapshot.lists_posts?(data),
          tag_ids: data.fetch("tags", []).map { |tag| tag["id"] }.sort, created_by_id: by&.id, created_at: now)
        # A scheduled record shows nothing yet, so its copy changes nothing the
        # public can see (the moment it goes live is the content version's own
        # publication-time lookup, as for the record itself).
        # INTERIM, until Task 5: a scheduled CHANGE (a future `live_at` on a
        # live record) bumps now and not when it comes into force, so between
        # Task 2 and Task 5 a conditional GET keeps answering 304 with the old
        # page at that moment. Task 5 adds the part of the content version that
        # follows copies by the clock.
        PublicSite.bump_version! if row.live?
        version
      end
    end

    def readonly? = persisted?
  end
end
