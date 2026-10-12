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
    #
    # `columns:` narrows what is read (a list of names): a copy read without
    # its `blocks` has them as a missing attribute.
    def self.current_for(records, now: Time.current, columns: nil)
      newest = among(records).in_force(now).group(:record_type, :record_id).select(arel_table[:id].maximum)
      unscoped.where(id: newest).select(*(columns || column_names)).index_by { |version| [ version.record_type, version.record_id ] }
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
        # The copy this one follows, read before anything is written: what
        # the public saw until now.
        previous = mine.in_force(now).order(id: :desc).first
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
        # The addresses this copy can change, in this transaction (derived
        # rows are refreshed with the write, after the record's row was
        # locked above: the order every sync from a save has). A copy with a
        # time changes none yet: the sweep does when its time has come
        # (`PublicSite::Paths.sync_copies_went_live`).
        PublicSite::Paths.published(row, version, previous) if live_at <= now
        version
      end
    end

    # THE ONE WRITE TO A COPY AFTER IT IS TAKEN, for `Tags::Merge` alone
    # (`test/lib/publishing_guards_test.rb` holds both halves). A tag's id in
    # a copy is a reference, not content: the tags a post's copy carries
    # (`tag_ids`) and the tag a list block's filter recorded
    # (`listed_tag_id`) are what the public lists and the posts' addresses
    # are matched by, and a merge deletes the tag `from` names. Left alone,
    # every copy would point at a tag that no longer exists, and the next
    # publish of the page or of a post, alone, would drop posts from a list
    # and take their addresses. So the id is replaced by the kept tag's in
    # every copy, in force, pending and older (an older copy is in force
    # again for a moment when its record is published after an unpublish):
    # after a merge the public lists and addresses are what they were.
    #
    # A list block that recorded NO id and names `from` by name found it by
    # that name until now (`Publishing::Listing#tag_id_of`), and the name is
    # about to name nothing: it records the kept tag's id, which is what it
    # listed by. What a visitor READS is not touched: the tag names in a
    # post's copy and the name in a block's settings change when the record
    # is published.
    #
    # Rows are written around `readonly?` with `update_all`, one statement
    # per copy that holds the id. In the caller's transaction, after its page
    # locks; it takes no lock of its own beyond the rows it writes.
    def self.repoint_tag!(from:, to:)
      carrying = unscoped.where(SqlNodes.array_contains(arel_table[:tag_ids], [ from.id ])).pluck(:id, :tag_ids)
      carrying.each do |id, tag_ids|
        unscoped.where(id: id).update_all(tag_ids: ((tag_ids - [ from.id ]) | [ to.id ]).sort) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end

      name = from.name.to_s.strip.downcase
      unscoped.where(lists_posts: true).select(:id, :blocks).find_each do |copy|
        blocks = copy.blocks.map do |block|
          recorded = block["listed_tag_id"]
          named = recorded.nil? && block.dig("settings", "tag").to_s.strip.downcase == name
          next block unless BlockTypes.find(block["block_type"])&.capability?(:lists_posts) && (recorded == from.id || named)

          block.merge("listed_tag_id" => to.id)
        end
        next if blocks == copy.blocks

        unscoped.where(id: copy.id).update_all(blocks: blocks) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end
    end

    def readonly? = persisted?
  end
end
