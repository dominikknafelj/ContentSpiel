module Dashboard
  # "Waiting for you" on the dashboard: the records that wait on someone,
  # for one of two reasons -- an open thread (`Dashboard::OpenThreads`) or
  # changes not yet published (`Dashboard::Feed#unpublished_changes`) --
  # merged into one list, the newest first. A record with both is ONE row
  # carrying both reasons, so a page is never listed twice in the panel.
  #
  # The filter picks the sources: "threads" reads open threads alone,
  # "unpublished" the unpublished changes alone, each row then carrying that
  # one reason; "everything" reads both. Under "everything" each source is
  # read at `limit` and the rows are grouped by record, sorted by their
  # newest time and cut to `limit`. Reading each source at `limit` is
  # enough: a record outside a source's top `limit` has `limit` distinct
  # newer records ahead of it in that source, each of them a row at least as
  # new, so it cannot be in the merged top `limit` on that source's time.
  # A kept row may still have the other reason with an older time outside
  # the other source's top, so after the cut each row is completed with the
  # reason its source did not bring: a page's or post's unpublished changes
  # are read from the loaded record in memory (`Publishing::State#changes?`),
  # and the feed's rows' open threads in one `OpenThreads` read narrowed to
  # those records. The completed reason is never newer than the row's time
  # (it would have been in its source's top `limit` otherwise), so the
  # order holds.
  #
  # Nothing here reads beyond the two sources but who may publish: one
  # scoped `pluck` of ids per model among the unpublished rows, skipped for
  # a model with none. Both sources are read-scoped (`AccessControl.scope`,
  # `Notes.readable_threads`, which hide the trash), and so is the pluck: a
  # record outside the viewer's scope leaves no row. The statements are
  # bounded by the kinds of record, never by the rows: the narrowed thread
  # read runs only when a row came from the feed alone, and each pluck only
  # for a model with an unpublished row.
  #
  # Ties go by the record's id, then its model (`#rank`): a page and a post
  # may share a time and an id, and `max_by` and `sort_by` are not stable.
  #
  # A row's routes are names (`Audit::Sentence::Route`), resolved by the
  # component that draws the row, which also picks the words.
  class WaitingForYou
    FILTERS = %w[everything threads unpublished].freeze
    REASONS = %i[thread unpublished].freeze

    # `reasons`: a frozen, non-empty subset of `REASONS`, in that order.
    # `thread`: the `OpenThreads::Row` when `:thread` is a reason.
    # `unpublished_at`: the record's `unpublished_changes_at` when
    # `:unpublished` is a reason. `at`: the newer of the two times.
    # `route`: the thread's (the editor with its notes open) when `:thread`
    # is a reason, else the record's editor. `review_route`: the editor
    # asked to open "Publish changes", when `:unpublished` is a reason and
    # the viewer may publish the record; else nil.
    Row = Data.define(:reasons, :at, :record, :thread, :unpublished_at, :route, :review_route)

    PUBLISH = { "Page" => "pages.publish", "Post" => "posts.publish" }.freeze

    attr_reader :filter

    def initialize(actor:, filter: "everything", channel: Current.channel, limit: 5)
      @actor = actor
      @filter = FILTERS.include?(filter) ? filter : "everything"
      @channel = channel
      @limit = limit
    end

    def rows
      @rows ||= begin
        entries = case filter
        when "threads" then threads.map { |row| { record: row.record, thread: row } }
        when "unpublished" then unpublished.map { |record| { record:, unpublished: true } }
        else completed(merged)
        end
        publishable = publishable_ids(entries.select { |entry| entry[:unpublished] }.map { |entry| entry[:record] })
        entries.map { |entry| row(entry, publishable) }.sort_by { |row| rank(row.at, row.record) }.reverse
      end
    end

    # How many records wait under the filter, the rows shown and beyond
    # them: the panel's count. Read from the same scoped sources as the rows
    # (`OpenThreads#record_keys`, `Feed#unpublished_keys`), a constant number
    # of statements; under "everything" a record with both reasons counts
    # once.
    def total
      @total ||= case filter
      when "threads" then open_threads.record_keys.size
      when "unpublished" then feed.unpublished_keys.size
      else (open_threads.record_keys | feed.unpublished_keys).size
      end
    end

    private

    def open_threads = @open_threads ||= OpenThreads.new(actor: @actor, channel: @channel, limit: @limit)

    def feed = @feed ||= Feed.new(actor: @actor, channel: @channel)

    def threads = open_threads.rows

    def unpublished = feed.unpublished_changes(limit: @limit)

    # Both sources grouped by record, the newest `limit` kept.
    def merged
      entries = {}
      threads.each { |row| (entries[key(row.record)] ||= { record: row.record })[:thread] = row }
      unpublished.each { |record| (entries[key(record)] ||= { record: })[:unpublished] = true }
      entries.values.max_by(@limit) { |entry| rank(newest(entry), entry[:record]) }
    end

    # Each kept entry with the reason its source did not bring.
    def completed(entries)
      entries.each { |entry| entry[:unpublished] ||= publishable_kind?(entry[:record]) && Publishing::State.of(entry[:record]).changes? }
      bare = entries.reject { |entry| entry[:thread] }
      return entries if bare.empty?

      found = OpenThreads.new(actor: @actor, channel: @channel, limit: bare.size, records: bare.map { |entry| entry[:record] }).rows.index_by { |row| key(row.record) }
      bare.each { |entry| entry[:thread] = found[key(entry[:record])] }
      entries
    end

    def row(entry, publishable)
      record, thread = entry[:record], entry[:thread]
      unpublished_at = record.unpublished_changes_at if entry[:unpublished]
      editor = Audit::Sentence.route_for(record)
      Row.new(
        reasons: REASONS.select { |reason| reason == :thread ? thread : unpublished_at }.freeze,
        at: [ thread&.at, unpublished_at ].compact.max, record:, thread:, unpublished_at:,
        route: thread ? thread.route : editor,
        review_route: (editor.with(params: { review: "publish" }) if unpublished_at && publishable.include?(key(record))))
    end

    # `[type, id]` of every record among `records` the viewer may publish:
    # one scoped pluck per model that has any.
    def publishable_ids(records)
      records.group_by { |record| record.class.base_class }.flat_map do |model, list|
        AccessControl.scope(@actor, PUBLISH.fetch(model.name), model.where(id: list.map(&:id)), channel: @channel)
          .pluck(:id).map { |id| [ model.name, id ] }
      end.to_set
    end

    # An image has threads but no publishing.
    def publishable_kind?(record) = PUBLISH.key?(record.class.base_class.name)

    def newest(entry) = [ entry[:thread]&.at, (entry[:record].unpublished_changes_at if entry[:unpublished]) ].compact.max

    def rank(at, record) = [ at, record.id, record.class.base_class.name ]

    def key(record) = [ record.class.base_class.name, record.id ]
  end
end
