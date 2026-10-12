module Publishing
  # One published copy of a page or post. Its content is written once, by
  # `take!`, and never changed (`readonly?`); the only row ever removed is one
  # whose `live_at` is still in the future, replaced by the next `take!`. Two
  # things about a copy that are not its content are written afterwards, each
  # by one method here: `settled_at` (`settle!`) and a merged tag's id
  # (`repoint_tag!`).
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
    #
    # Answers the copy, which says through `yields` what the addresses did
    # with it: the changes that had to yield (`PublicSite::Paths.refresh`),
    # empty for a copy with a time, whose addresses follow when it is due.
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
          tag_ids: data.fetch("tags", []).map { |tag| tag["id"] }.sort, created_by_id: by&.id, created_at: now,
          settled_at: (now if live_at <= now && row.published_at&.<=(now)))
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
        # locked above: the order every refresh from a save has). In force
        # at once, its record is what was touched; it is settled as it is
        # written when the record is live, and left to become due when the
        # record is only scheduled. A copy with a time changes no address
        # yet. Either is settled by the first refresh after its moment
        # (`settle!`).
        version.yields = live_at <= now ? PublicSite::Paths.refresh(**{ (row.is_a?(Page) ? :pages : :posts) => [ row ] }, now: now) : []
        version
      end
    end

    # What `take!` learned from the addresses; not stored.
    attr_accessor :yields

    # THE COPIES THAT ARE DUE: showing by the clock and not acted on yet.
    # A copy shows from the later of two moments, its own time (`live_at`)
    # and its record's (`published_at`): a change published with a time
    # comes into force at the first, the copy of a scheduled page or post is
    # in force at once and shown when the record goes live. Neither moment
    # writes a row, and this is what stands for both: `settled_at` is set by
    # `take!` for a copy that shows at once, and here for every other, once,
    # however long ago its moment came. Nothing has to remember a window,
    # and a scheduled record moved to another time needs nothing kept in
    # step: its copy is due when the record is live, whenever that is.
    #
    # Marks them and answers `[[id, record type, record id], ...]`, for
    # `PublicSite::Paths.refresh` alone, which re-derives the addresses of
    # those records in the same transaction.
    #
    # One statement when no copy is waiting (nearly always): the partial
    # index it reads holds the scheduled records' copies and nothing else
    # that is in force. When some are, their records' times are read (a
    # statement per record type), and the rows that are due are locked as
    # they are read again, so of two refreshes at once the second waits and
    # then finds nothing left to mark.
    def self.settle!(now = Time.current)
      waiting = unscoped.where(settled_at: nil, live_at: ..now).pluck(:id, :record_type, :record_id)
      return [] if waiting.empty?

      shown = waiting.group_by { |_, type, _| type }.flat_map do |type, copies|
        type.constantize.where(id: copies.map(&:last), published_at: ..now).ids.map { |id| [ type, id ] }
      end
      ids = waiting.filter_map { |id, type, record_id| id if shown.include?([ type, record_id ]) }
      return [] if ids.empty?

      due = unscoped.where(id: ids, settled_at: nil).order(:id).lock.pluck(:id, :record_type, :record_id)
      unscoped.where(id: due.map(&:first)).update_all(settled_at: now) # version: none (a mark on a copy, not content: the refresh that follows bumps for an address that moves)
      due
    end

    # THE ONE WRITE TO WHAT A COPY REFERS TO after it is taken, for
    # `Tags::Merge` alone (`test/lib/publishing_guards_test.rb` holds both
    # halves). A tag's id in a copy is a reference, not content: the tags a
    # post's copy carries (`tag_ids`) and the tag a list block's filter
    # recorded (`listed_tag_id`) are what the public lists and the posts'
    # addresses are matched by, and a merge deletes the tag `from` names.
    # Left alone, every copy would point at a tag that no longer exists, and
    # the next publish of the page or of a post, alone, would drop posts
    # from a list and take their addresses. So the id is replaced by the
    # kept tag's in every copy, in force, pending and older (an older copy
    # is in force again for a moment when its record is published after an
    # unpublish). After a merge the lists that held the merged tag's posts
    # still hold them. The two ids are one from then on, so a list that
    # filters by either holds the carriers of both: a post of the KEPT tag
    # that nobody touched can move to a list that filtered by the merged
    # one (`Tags::Merge` refreshes the pages and posts of both).
    #
    # What a visitor READS is not touched: the tag names in a post's copy
    # and the name in a block's settings change when the record is
    # published. A list block that recorded NO id lists nothing and is left
    # so, whatever name it holds.
    #
    # Rows are written around `readonly?` with `update_all`, one statement
    # per copy that holds the id, and only those copies are read: the array
    # by its index, the blocks by containment (`listing_tag`). In the
    # caller's transaction, after its page locks; it takes no lock of its
    # own beyond the rows it writes.
    def self.repoint_tag!(from:, to:)
      unscoped.where(SqlNodes.array_contains(arel_table[:tag_ids], [ from.id ])).pluck(:id, :tag_ids).each do |id, tag_ids|
        unscoped.where(id: id).update_all(tag_ids: ((tag_ids - [ from.id ]) | [ to.id ]).sort) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end

      listing_tag([ from.id ]).pluck(:id, :blocks).each do |id, blocks|
        blocks = blocks.map { |block| block["listed_tag_id"] == from.id ? block.merge("listed_tag_id" => to.id) : block }
        unscoped.where(id: id).update_all(blocks: blocks) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end
    end

    # The copies of pages one of whose blocks recorded one of these tag ids
    # as its filter (`listed_tag_id`): in force, pending and older alike.
    def self.listing_tag(tag_ids)
      tag_ids.map { |id| SqlNodes.json_contains(arel_table[:blocks], [ { "listed_tag_id" => id } ]) }
        .reduce(:or).then { |holding| holding ? unscoped.where(record_type: "Page", lists_posts: true).where(holding) : none }
    end

    def readonly? = persisted?
  end
end
