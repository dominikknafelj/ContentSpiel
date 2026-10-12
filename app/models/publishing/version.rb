module Publishing
  # One published copy of a page or post. Its content is written once, by
  # `take!`, and never changed (`readonly?`); the only row ever removed is one
  # whose `live_at` is still in the future: replaced by the next `take!`, or
  # withdrawn (`withdraw_pending!`: "Cancel scheduled change", and a discard).
  # Two things about a copy are written afterwards, each by one method here:
  # `settled_at` (`settle!`), which is not its content, and a merged tag
  # (`repoint_tag!`): its id wherever the copy refers to it, the id and name
  # a post's copy shows of it and the name a copied list block's filter
  # holds, the one piece of content ever rewritten.
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
    # THE ADDRESSES FOLLOW THE COPY: a copy that is in force at once ends
    # with its record's own refresh (`Publishing.keep_address!`, the one
    # check that can refuse a publish for an address, and only for the
    # record's OWN: see there). `shown:` is what the caller knows and the row
    # no longer says: the record was on the site before this copy ("Publish
    # changes"), so an address it already stood without is not this copy's
    # doing. Another record that yields for this copy yields, as for any
    # other write; nobody is asked beforehand.
    #
    # A copy with a time of its own moves no address now and is asked
    # nothing: when its time comes the first refresh settles it (`settle!`),
    # whatever has to yield then yields, and the clash is reported.
    def self.take!(record, live_at: nil, by: nil, now: Time.current, shown: false)
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
        # publication-time lookup, as for the record itself). A scheduled
        # CHANGE (a future `live_at` on a live record) changes nothing now
        # either: it comes into force when its time passes, which is the part
        # of `PublicSite.content_version` that reads the newest `live_at` in
        # force, so no write and no job is what moves the version then.
        PublicSite.bump_version! if row.live? && live_at <= now
        # The rows and the newest copy are the same now, so nothing is waiting.
        # Inside this transaction: a publish that is refused or rolled back
        # (the address below raises) leaves the mark where it was.
        Publishing.clear_changes(row)
        # The images the copies show count as used (`Media::Usage` role
        # `published`), in this transaction, whether the copy is in force now
        # or pending.
        Media::UsageIndex.refresh_published(row, now: now)
        # In this transaction, after the record's row was locked above: the
        # order every refresh from a save has. A copy of a record that is
        # only scheduled is in force too and is refreshed now (a scheduled
        # record has an address); it is left unsettled, and becomes due when
        # the record goes live.
        Publishing.keep_address!(row, now: now, shown: shown) if live_at <= now

        version
      end
    end

    # WITHDRAWS THE COPY THAT WAITS FOR ITS TIME, if there is one: a pending
    # copy was never public, so it may be deleted (drafts spec §7). Answers the
    # numbers of what was removed (none or one); a number is not given out
    # again. For `Publishing::CancelScheduledChange` and
    # `Publishing::DiscardChanges` alone (`test/lib/publishing_guards_test.rb`),
    # each of which holds the record's row lock, as `take!` does, and
    # refreshes the images in use afterwards. Nothing public moves: a pending
    # copy has given no address and is no part of the content version.
    def self.withdraw_pending!(record, now: Time.current)
      waiting = of(record).pending(now)
      numbers = waiting.pluck(:number)
      waiting.delete_all if numbers.any? # version: none (a pending copy was never public)
      numbers
    end

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
    # index it reads holds, of the copies in force, those of the scheduled
    # records and nothing else for long. A copy of a record that is NOT
    # published (its schedule was removed, or it was unpublished with a
    # change pending) will never be due, since publishing the record again
    # takes a new copy; it is marked here the first time it is met, with no
    # refresh, so it costs no statement after that. When some are waiting,
    # their records' times are read (a statement per record type), and the
    # rows to mark are locked as they are read again, so of two refreshes at
    # once the second waits and then finds nothing left to mark.
    def self.settle!(now = Time.current)
      waiting = unscoped.where(settled_at: nil, live_at: ..now).pluck(:id, :record_type, :record_id)
      return [] if waiting.empty?

      times = waiting.group_by { |_, type, _| type }.flat_map do |type, copies|
        type.constantize.where(id: copies.map(&:last)).pluck(:id, :published_at).map { |id, time| [ [ type, id ], time ] }
      end.to_h
      # A record that is still scheduled keeps its copy waiting.
      ids = waiting.filter_map { |id, type, record_id| id unless times[[ type, record_id ]]&.>(now) }
      return [] if ids.empty?

      marked = unscoped.where(id: ids, settled_at: nil).order(:id).lock.pluck(:id, :record_type, :record_id)
      unscoped.where(id: marked.map(&:first)).update_all(settled_at: now) # version: none (a mark on a copy, not content: the refresh that follows bumps for an address that moves)
      marked.select { |_, type, record_id| times[[ type, record_id ]] }
    end

    # THE ONE WRITE TO A COPY'S CONTENT after it is taken, for `Tags::Merge`
    # alone (`test/lib/publishing_guards_test.rb` holds both halves). A
    # tag's id in a copy is a reference, not content: the tags a post's copy
    # carries (`tag_ids`) and the tag a list block's filter recorded
    # (`listed_tag_id`) are what the public lists and the posts' addresses
    # are matched by, and a merge deletes the tag `from` names. Left alone,
    # every copy would point at a tag that no longer exists, and the next
    # publish of the page or of a post, alone, would drop posts from a list
    # and take their addresses. So the id is replaced by the kept tag's in
    # every copy, in force, pending and older (an older copy is in force
    # again for a moment when its record is published after an unpublish).
    # After a merge the lists that held the merged tag's posts still hold
    # them. The two ids are one from then on, so a list that filters by
    # either holds the carriers of both: a post of the KEPT tag that nobody
    # touched can move to a list that filtered by the merged one
    # (`Tags::Merge` refreshes the pages and posts of both).
    #
    # WHAT A VISITOR READS OF THE TAG FOLLOWS, in the same statement: a
    # post's copy holds its tags by id AND NAME (`snapshot["tags"]`, what
    # `Snapshot.tags_from` hands the public post and the lists), and the
    # merged tag is no tag any more. This used to leave the name alone
    # "until the post is published", and a hand test found the site printing
    # "rails" beside "ruby" after the one had been merged into the other,
    # with every carrier marked as having unpublished changes, for a merge
    # the dialog calls immediate. So the merged tag's entry becomes the kept
    # tag's, id and name, where it stood (`merged_tags`); a copy that
    # carried the kept tag already keeps that entry as it is and loses the
    # merged one, so the tag is there once and the others keep their order.
    # A copy's rows and a carrier's rows then say the same about the tag,
    # which is why the merge marks no post (`Tags::Listings#touch_carrying_posts`).
    #
    # THE NAME A LIST BLOCK'S FILTER HOLDS FOLLOWS TOO: a copied list block
    # that recorded the merged tag's id gets the kept tag's id and, in its
    # `settings`, the kept tag's name, as `Tags::Merge#repoint_blocks`
    # writes the row's block. No visitor reads that name (the list is
    # matched by `listed_tag_id`), but the overview compares it, and left
    # alone every such page stood marked "Unpublished changes" with a
    # "Changed: Post list" that published nothing anyone could see. So A
    # MERGE MARKS NOTHING: not a post, not a page. A list block that
    # recorded NO id lists nothing and is left so, whatever name it holds
    # (its page differed from its rows before the merge and still does).
    #
    # Rows are written around `readonly?` with `update_all`, one statement
    # per copy that holds the id, and only those copies are read: the array
    # by its index, the blocks by containment (`listing_tag`). In the
    # caller's transaction, after its page locks; it takes no lock of its
    # own beyond the rows it writes. `to` is the caller's LOCKED row: its
    # name is the one the rows show.
    def self.repoint_tag!(from:, to:)
      unscoped.where(SqlNodes.array_contains(arel_table[:tag_ids], [ from.id ])).pluck(:id, :tag_ids, :snapshot).each do |id, tag_ids, snapshot|
        shown = snapshot.key?("tags") ? snapshot.merge("tags" => merged_tags(snapshot["tags"], from, to)) : snapshot
        unscoped.where(id: id).update_all(tag_ids: ((tag_ids - [ from.id ]) | [ to.id ]).sort, snapshot: shown) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end

      listing_tag([ from.id ]).pluck(:id, :blocks).each do |id, blocks|
        blocks = blocks.map do |block|
          next block unless block["listed_tag_id"] == from.id

          block.merge("listed_tag_id" => to.id, "settings" => (block["settings"] || {}).merge("tag" => to.name))
        end
        unscoped.where(id: id).update_all(blocks: blocks) # version: none (Tags::Merge, the one caller, bumps for the whole merge)
      end
    end

    # A copy's tags (`[{ "id" =>, "name" => }, ...]`) after `from` was merged
    # into `to`: `from`'s entry is `to`'s, in its place, unless the copy
    # carried `to` already, whose own entry then stands for both. Nothing
    # else moves.
    def self.merged_tags(tags, from, to)
      carried = tags.any? { |tag| tag["id"] == to.id }
      tags.filter_map do |tag|
        next tag unless tag["id"] == from.id

        { "id" => to.id, "name" => to.name } unless carried
      end
    end
    private_class_method :merged_tags

    # The copies of pages one of whose blocks recorded one of these tag ids
    # as its filter (`listed_tag_id`): in force, pending and older alike.
    def self.listing_tag(tag_ids)
      tag_ids.map { |id| SqlNodes.json_contains(arel_table[:blocks], [ { "listed_tag_id" => id } ]) }
        .reduce(:or).then { |holding| holding ? unscoped.where(record_type: "Page", lists_posts: true).where(holding) : none }
    end

    def readonly? = persisted?
  end
end
