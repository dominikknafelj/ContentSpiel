module Dashboard
  # The dashboard's "Recent activity" (design pass round 2, Task 16): one feed
  # of the newest *content* audit events -- pages, posts, blocks and library
  # images, never `access.denied`, `session.*`, `user.*`, `group.*`,
  # `token.*` or `settings.*` -- limited to what the viewer may read NOW.
  # A record they can't read (or that is trashed, or gone: a purge, a
  # deleted block) leaves no row at all, not a "something happened" line, so
  # the feed can't be used to learn that a locked-out record exists
  # ("not found, not forbidden"). That includes the record's own
  # `*.trashed` event: only a kept record is listed, so a trashed page's
  # whole history disappears from the feed with it and reappears if it is
  # restored.
  #
  # The read scope is applied IN SQL, in the one event query (a ruling of
  # fix round 1, replacing an earlier over-fetch-then-filter in Ruby): that
  # shape under-filled -- sixty uploads by someone else, or a busy site
  # outside a branch grant, emptied the feed for a viewer who couldn't read
  # them, and the feed's length leaked how much hidden activity there is.
  # The query reads
  #
  #   action IN (allow-list) AND last_occurred_at > now - WINDOW AND (
  #     Page subject IN (readable pages) OR Post subject IN (readable posts)
  #     OR ContentBlock subject whose owner is a readable page/post
  #     OR (media.upload holders only) a kept image, current or legacy type )
  #   ORDER BY last_occurred_at DESC, id DESC LIMIT n
  #
  # where "readable" is `AccessControl.scope(...).select(:id)` as a subquery
  # (so it already hides the trash and honours branch/content-type/own
  # scopes). Each branch is only added when the viewer `holds?` the right at
  # all, so a viewer with no grants runs no query. `WINDOW` bounds the scan
  # of an ever-growing table; `index_audit_events_on_recent` serves the
  # ORDER BY ... LIMIT.
  #
  # Queries, constant whatever the data size: that one event query, one
  # lookup of the blocks those events are about (a block event's subject is
  # the block, but the sentence is about the page or post that owns it), one
  # read-scoped query per subject type loading the records (kept, scoped
  # again as defence in depth -- the rows can't have changed between the two
  # queries in a way that leaks, but a record trashed in between simply
  # drops out), and one preload of the events' users.
  #
  # RUNS: events of a COLLAPSING action by the same person (user, actor type
  # and id) on the same record (any image, for uploads), each at most
  # `Audit::COALESCE_WINDOW` older than the run's newest, are ONE row with a
  # count -- "added 4 Code blocks to “…”", "uploaded 12 images". They are
  # joined in Ruby over the events the one query already read (READ_FACTOR
  # times the limit), after the unreadable and the gone are left out, so such
  # an event neither shows nor splits a run, and the statement count does not
  # change. A block deleted since is no event here (its record is gone) and
  # is not counted; the count is of distinct subjects.
  #
  # A change made through an API token is shown as its *user's* (the event's
  # `user_id`, filled for a user and a token alike), the sentence's actor
  # carrying the token's name as recorded on the event
  # (`Audit::Event#via_label`); the token itself is never loaded.
  class Activity
    # How far back the feed looks: the scan bound for a large audit table.
    WINDOW = 90.days

    # Which actions are listed: purges and a block's deletion leave no
    # subject to link to, so they aren't here. The WORDING of each is not this
    # class's business: `Audit::Sentence` words every event, for this feed and
    # the audit log alike.
    ACTIONS = {
      "page" => %w[created updated published unpublished moved trashed restored translation_confirmed],
      "post" => %w[created updated published unpublished scheduled trashed restored translation_confirmed],
      "media" => %w[uploaded updated trashed restored translation_confirmed],
      "block" => %w[created updated reordered translation_confirmed],
      # A note's start and its resolve only: replies are left out so they
      # don't flood the feed.
      "note" => %w[started resolved]
    }.flat_map { |prefix, verbs| verbs.map { |verb| "#{prefix}.#{verb}" } }.freeze

    # Data only, no markup and no view component: `sentence` is the
    # `Audit::Sentence` (the actor as facts -- the viewer, a user, a deleted
    # user, nobody -- plus the token's name for a change made through one, and
    # the sentence's parts); `ActivityRowComponent` renders it, naming the user
    # through `Admin::Ui::UserNameComponent`. `at` is when the (first) change
    # happened and `span_end` when the coalesced burst last extended (nil for a
    # single moment). `record` is the page, post or image the sentence is
    # about (a block's owner).
    #
    # `count` is how many events a collapsed run holds (1 for an ordinary
    # row); then `event` is the run's newest, `at` its oldest event's start and
    # `span_end` the newest's last extension.
    Row = Data.define(:event, :record, :sentence, :at, :span_end, :count) do
      def initialize(count: 1, **rest) = super(count:, **rest)
    end

    # The event query reads this many times the rows wanted, so that a run
    # collapsed into one row still leaves `limit` rows to show; a feed whose
    # newest events all collapse shows fewer rows than `limit` rather than
    # reading more (the cost is a longer LIMIT, never another statement).
    READ_FACTOR = 4

    # The actions a run of the same person on the same record joins into one
    # row (blocks added or updated, uploads): `Audit::Sentence` words them.
    COLLAPSING = Audit::Sentence::COUNTED

    def initialize(actor:, channel: Current.channel, limit: 15)
      @actor = actor
      @channel = channel
      @limit = limit
    end

    def rows
      @rows ||= build_rows
    end

    private

    def build_rows
      readable = readable_subjects
      return [] unless readable # nothing readable: no query at all

      events = Audit::Event.where(action: ACTIONS).where(last_occurred_at: WINDOW.ago..).and(readable)
        .order(last_occurred_at: :desc, id: :desc).limit(@limit * READ_FACTOR).to_a
      return [] if events.empty?

      records = readable_records(events)
      ActiveRecord::Associations::Preloader.new(records: events, associations: :user).call
      runs(events, records).first(@limit).map { |run| row_for(run) }
    end

    # The events whose subject the viewer may read (see the class comment), as
    # a relation holding only that condition -- the branches joined by OR --
    # for `and`; nil for a viewer who can read nothing.
    def readable_subjects
      events = Audit::Event.all
      pages = readable_ids(Page, "pages.read")
      posts = readable_ids(Post, "posts.read")
      branches = []
      branches << events.where(subject_type: "Page", subject_id: pages) if pages
      branches << events.where(subject_type: "Post", subject_id: posts) if posts
      owners = []
      owners << ContentBlock.where(owner_type: "Page", owner_id: pages) if pages
      owners << ContentBlock.where(owner_type: "Post", owner_id: posts) if posts
      branches << events.where(subject_type: "ContentBlock", subject_id: owners.reduce(:or).select(:id)) if owners.any?
      if AccessControl.holds?(@actor, "media.upload", channel: @channel)
        types = [ "Media::Asset" ] + Audit::Event::LEGACY_POLYMORPHIC_TYPES.keys
        branches << events.where(subject_type: types, subject_id: Media::Asset.kept.select(:id))
      end
      branches.reduce(:or)
    end

    # The ids (a `SELECT id` subquery) of the records of `model` the viewer may
    # read, or nil when they hold no such right at all (so no subquery is
    # built).
    def readable_ids(model, key)
      return unless AccessControl.holds?(@actor, key, channel: @channel)

      AccessControl.scope(@actor, key, model.all, channel: @channel).unscope(:order).select(:id)
    end

    # `[[event, record], ...]` per run, newest first. An event whose record
    # the viewer can't read (or is gone) is left out BEFORE the runs are
    # made, so it neither shows nor splits one.
    def runs(events, records)
      events.filter_map { |event| (record = records[subject_key(event)]) && [ event, record ] }
        .each_with_object([]) do |pair, runs|
          if runs.last && joins?(runs.last, *pair) then runs.last << pair
          else runs << [ pair ]
          end
        end
    end

    def joins?(run, event, record)
      newest, newest_record = run.first
      COLLAPSING.include?(event.action) && event.action == newest.action && actor_key(event) == actor_key(newest) &&
        (event.action == "media.uploaded" || record == newest_record) &&
        newest.last_occurred_at - event.last_occurred_at <= Audit::COALESCE_WINDOW
    end

    def actor_key(event) = [ event.user_id, event.actor_type, event.actor_id ]

    def row_for(run)
      event, record = run.first
      oldest = run.last.first
      count = run.map { |(e, _)| e.subject_id }.uniq.size
      mixed = run.map { |(e, _)| e.snapshot.is_a?(Hash) ? e.snapshot["block_type"] : nil }.uniq.size > 1
      fallback = (record.published_at if record.respond_to?(:published_at))
      target =
        if count > 1 && event.action == "media.uploaded"
          Audit::Sentence::Target.new(nil, Audit::Sentence.library_route)
        else
          Audit::Sentence::Target.new(record.title.presence || "(untitled)", Audit::Sentence.route_for(record))
        end
      sentence = Audit::Sentence.build(event, viewer: @actor, target:, fallback_scheduled_at: fallback, count:, mixed:)
      Row.new(event:, record:, sentence:, at: oldest.occurred_at, count:,
        span_end: (event.last_occurred_at if event.last_occurred_at > oldest.occurred_at))
    end

    # Where an event's sentence points: `[class name, id]` of the page, post
    # or image. A block's event reaches its owner through `@blocks`;
    # `block.reordered` already names the page as its subject.
    def subject_key(event)
      type = normalized_type(event.subject_type)
      if type == "ContentBlock"
        block = @blocks[event.subject_id] or return
        [ block.owner_type, block.owner_id ]
      else
        [ type, event.subject_id ]
      end
    end

    def normalized_type(type) = Audit::Event::LEGACY_POLYMORPHIC_TYPES.fetch(type, type)

    # `{ [class name, id] => record }`: the kept records the viewer may read
    # among everything the events are about, one query per model.
    def readable_records(events)
      by_type = events.group_by { |event| normalized_type(event.subject_type) }
      @blocks = ContentBlock.where(id: (by_type["ContentBlock"] || []).map(&:subject_id)).index_by(&:id)
      ids = Hash.new { |hash, key| hash[key] = [] }
      by_type.each { |type, list| ids[type] += list.map(&:subject_id) unless type == "ContentBlock" }
      @blocks.each_value { |block| ids[block.owner_type] << block.owner_id }

      {
        "Page" => ("pages.read" if ids["Page"].any?), "Post" => ("posts.read" if ids["Post"].any?)
      }.compact.flat_map do |type, key|
        AccessControl.scope(@actor, key, type.constantize.where(id: ids[type].uniq), channel: @channel).map { |record| [ [ type, record.id ], record ] }
      end.to_h.merge(readable_media(ids["Media::Asset"]))
    end

    def readable_media(ids)
      return {} if ids.empty? || !AccessControl.holds?(@actor, "media.upload", channel: @channel)

      Media::Asset.kept.where(id: ids.uniq).to_h { |asset| [ [ "Media::Asset", asset.id ], asset ] }
    end
  end
end
