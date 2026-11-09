module Dashboard
  # Open threads on the dashboard: the records the viewer
  # may read that have open threads, one row per record with how many, the
  # most recently active first. One grouped query over
  # `Notes.readable_threads` (the read scope and the trash are in it), then
  # one read per kind of record among the rows, one for who wrote last on
  # each of them (the newest message among the record's open threads the
  # viewer may read, `Notes::Message.newest_per_container`), one for everybody
  # who wrote on them (`Notes::Message.authors_per_container`) and one for
  # those people: the same statements for one row as for eight. Nothing here
  # is about the viewer's own unread notes: the count is everybody's, and
  # neutral.
  #
  # `records:` narrows the read to those records' threads (the merged panel
  # asks which of its unpublished records are also discussed); nil reads
  # every record. The narrowing is inside the readable threads, so a record
  # handed in that the viewer may not read still has no row. The records
  # handed in are already loaded (and kept: the caller read them through
  # the read scope), so they are not read again.
  #
  # `last_author` is that person as a user, `last_author_id` their id when
  # the user is gone (the row then says "a deleted user"); both nil once the
  # foreign key has nulled the column.
  #
  # `with_authors: true` also reads who wrote on each record's open threads,
  # in one more statement for all the rows: `authors` are the newest two
  # people, the newest first, and `author_count` how many people wrote (a
  # deleted user is a nil among the authors and one in the count). Without it they are empty and zero,
  # and nothing is read: Waiting for you has no use for them.
  #
  # `more_records` is how many records with open threads the viewer may read
  # lie beyond the rows: one statement, `record_keys`, asked only when it is
  # read.
  #
  # A row leads to the record with its notes open -- its editor's drawer, or
  # for an image the Media screen with that image chosen, whose panel shows
  # its notes -- as a route NAME, which the component that draws the row
  # resolves.
  class OpenThreads
    # How many people a row names.
    SHOWN_AUTHORS = 2

    Row = Data.define(:record, :kind, :title, :count, :at, :route, :last_author, :last_author_id, :authors, :author_count)

    def initialize(actor:, channel: Current.channel, limit: 5, records: nil, with_authors: false)
      @actor = actor
      @channel = channel
      @limit = limit
      @records = records
      @with_authors = with_authors
    end

    def rows
      @rows ||= begin
        threads = Notes::Thread.arel_table
        newest = threads[:last_message_at].maximum
        groups = unresolved.group(:container_type, :container_id)
          .order(newest.desc, threads[:container_id].desc, threads[:container_type].desc).limit(@limit).pluck(:container_type, :container_id, Arel.star.count, newest)
        records = records_of(groups)
        author_ids = last_author_ids(groups)
        wrote = @with_authors ? writers(groups) : {}
        authors = (author_ids.values + wrote.values.flatten(1).map(&:first)).compact.then { |ids| ids.empty? ? {} : User.where(id: ids.uniq).index_by(&:id) }
        groups.filter_map do |type, id, count, at|
          record = records[[ type, id ]] or next
          base = Audit::Sentence.route_for(record)
          route = record.is_a?(Media::Asset) ? base : base.with(params: base.params.merge(notes: "open"))
          author_id = author_ids[[ type, id ]]
          Row.new(record: record, kind: NotesForYou::KINDS.fetch(type), title: record.title.presence, count: count, at: at, route: route,
            last_author: authors[author_id], last_author_id: author_id,
            authors: wrote.fetch([ type, id ], []).first(SHOWN_AUTHORS).map { |writer_id, _| authors[writer_id] },
            author_count: wrote.fetch([ type, id ], []).size)
        end
      end
    end

    # How many records with open threads the viewer may read there are beyond
    # the rows: what the rail says as "And N more".
    def more_records = [ record_keys.size - rows.size, 0 ].max

    # `[type, id]` of every record the viewer may read that has an open
    # thread, on the rows shown and beyond them: what Waiting for you counts.
    # One statement, whatever the number of records.
    def record_keys = @record_keys ||= unresolved.distinct.pluck(:container_type, :container_id).to_set

    private

    # Not `open` and not `load`: both are `Kernel`'s, in every object.
    def unresolved
      threads = Notes.readable_threads(@actor, channel: @channel).unresolved
      @records.nil? ? threads : threads.and(on_containers(@records.map { |record| [ record.class.base_class.name, record.id ] }))
    end

    # The threads on the `[type, id]` pairs: one hash condition per kind of
    # record, or-ed; none at all for no pairs.
    def on_containers(pairs)
      pairs.group_by(&:first).map { |type, list| Notes::Thread.where(container_type: type, container_id: list.map(&:last)) }
        .reduce(:or) || Notes::Thread.none
    end

    # `{ [type, id] => author id }`: who wrote the newest message among each
    # listed record's open threads. One statement for all the rows.
    def last_author_ids(groups)
      return {} if groups.empty?

      listed = on_containers(groups.map { |row| row.first(2) })
      Notes::Message.newest_per_container.merge(unresolved.merge(listed)).to_h { |message| [ [ message[:container_type], message[:container_id] ], message.author_id ] }
    end

    # `{ [type, id] => [[author id, when they last wrote], ...] }`, the
    # newest first, of everybody who wrote on each listed record's open
    # threads. One statement for all the rows.
    def writers(groups)
      return {} if groups.empty?

      listed = on_containers(groups.map { |row| row.first(2) })
      Notes::Message.authors_per_container.merge(unresolved.merge(listed))
        .group_by { |message| [ message[:container_type], message[:container_id] ] }
        .transform_values { |messages| messages.map { |message| [ message.author_id, message[:last_wrote_at] ] } }
    end

    def records_of(groups)
      return @records.index_by { |record| [ record.class.base_class.name, record.id ] } if @records

      groups.group_by(&:first).flat_map do |type, list|
        type.constantize.kept.where(id: list.map { |row| row[1] }).map { |record| [ [ type, record.id ], record ] }
      end.to_h
    end
  end
end
