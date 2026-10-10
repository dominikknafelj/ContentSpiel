module Dashboard
  # "Open threads" on the dashboard (notes spec §5): the records the viewer
  # may read that have open threads, one row per record with how many, the
  # most recently active first. One grouped query over
  # `Notes.readable_threads` (the read scope and the trash are in it), then
  # one read per kind of record among the rows, one for who wrote last on
  # each of them (the newest message among the record's open threads the
  # viewer may read, `Notes::Message.newest_per_container`) and one for
  # those people: the same statements for one row as for five. Nothing here
  # is about the viewer's own unread notes: the count is everybody's, and
  # neutral.
  #
  # `last_author` is that person as a user, `last_author_id` their id when
  # the user is gone (the row then says "a deleted user"); both nil once the
  # foreign key has nulled the column.
  #
  # A row leads to the record with its notes open -- its editor's drawer, or
  # for an image the Media screen with that image chosen, whose panel shows
  # its notes -- as a route NAME (`Admin::NotesScreen::OpenThreadRowComponent`
  # resolves it).
  class OpenThreads
    Row = Data.define(:record, :kind, :title, :count, :at, :route, :last_author, :last_author_id)

    def initialize(actor:, channel: Current.channel, limit: 5)
      @actor = actor
      @channel = channel
      @limit = limit
    end

    def rows
      @rows ||= begin
        threads = Notes::Thread.arel_table
        newest = threads[:last_message_at].maximum
        groups = unresolved.group(:container_type, :container_id)
          .order(newest.desc, threads[:container_id].desc).limit(@limit).pluck(:container_type, :container_id, Arel.star.count, newest)
        records = records_of(groups)
        author_ids = last_author_ids(groups)
        authors = author_ids.values.compact.then { |ids| ids.empty? ? {} : User.where(id: ids.uniq).index_by(&:id) }
        groups.filter_map do |type, id, count, at|
          record = records[[ type, id ]] or next
          base = Audit::Sentence.route_for(record)
          route = record.is_a?(Media::Asset) ? base : base.with(params: base.params.merge(notes: "open"))
          author_id = author_ids[[ type, id ]]
          Row.new(record: record, kind: NotesForYou::KINDS.fetch(type), title: record.title.presence, count: count, at: at, route: route,
            last_author: authors[author_id], last_author_id: author_id)
        end
      end
    end

    # Every open thread the viewer may read, on the rows shown and beyond
    # them: the number in the card's header. One COUNT.
    def total = @total ||= unresolved.count

    private

    # Not `open` and not `load`: both are `Kernel`'s, in every object.
    def unresolved = Notes.readable_threads(@actor, channel: @channel).unresolved

    # `{ [type, id] => author id }`: who wrote the newest message among each
    # listed record's open threads. One statement for all the rows.
    def last_author_ids(groups)
      return {} if groups.empty?

      listed = groups.group_by(&:first).map { |type, list| Notes::Thread.where(container_type: type, container_id: list.map { |row| row[1] }) }.reduce(:or)
      Notes::Message.newest_per_container.merge(unresolved.merge(listed)).to_h { |message| [ [ message[:container_type], message[:container_id] ], message.author_id ] }
    end

    def records_of(groups)
      groups.group_by(&:first).flat_map do |type, list|
        type.constantize.kept.where(id: list.map { |row| row[1] }).map { |record| [ [ type, record.id ], record ] }
      end.to_h
    end
  end
end
