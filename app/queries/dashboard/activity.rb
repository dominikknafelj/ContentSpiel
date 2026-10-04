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
  # Constant number of queries, whatever the data size:
  #   1. ONE limited event query that over-fetches (`OVERFETCH` x the limit,
  #      newest first) -- the read scope can only be applied once the
  #      events' subjects are known, so we take more than we need,
  #   2. one lookup of the blocks those events are about (a block event's
  #      subject is the block, but the sentence is about the page or post
  #      that owns it),
  #   3. one read-scoped query per subject type (`AccessControl.scope` for
  #      pages and posts, which already hides the trash; kept images for a
  #      `media.upload` holder, the library having no per-record read scope),
  #   4. one preload of the events' users.
  # Nothing is queried per row. The price of over-fetching rather than
  # filtering in SQL is that a viewer who can read very little can see a
  # short feed even though older readable events exist beyond the window --
  # accepted: a read scope is a join through the closure table and grants,
  # and pushing it under an ORDER BY ... LIMIT is what the other dashboard
  # lists' LATERAL joins exist for; an activity feed of "the latest few
  # things" doesn't need that.
  #
  # A change made through an API token is shown as its *user's* (the event's
  # `user_id`, filled for a user and a token alike), flagged `via_token`;
  # the token itself is never loaded or named (round 3 brings token names).
  class Activity
    OVERFETCH = 4

    # Event action => what the sentence says before the record's title and
    # after it. A block's events are about its owner ("edited a block on
    # “About”"), so they are keyed by the same table with their own wording.
    SENTENCES = {
      "created" => [ "created", "" ], "updated" => [ "edited", "" ], "published" => [ "published", "" ],
      "unpublished" => [ "unpublished", "" ], "scheduled" => [ "scheduled", "" ], "moved" => [ "moved", "" ],
      "trashed" => [ "moved", " to the trash" ], "restored" => [ "restored", "" ],
      "uploaded" => [ "uploaded", "" ], "translation_confirmed" => [ "marked a translation of", " as up to date" ]
    }.freeze
    BLOCK_SENTENCES = {
      "created" => [ "edited a block on", "" ], "updated" => [ "edited a block on", "" ],
      "reordered" => [ "reordered blocks on", "" ], "translation_confirmed" => SENTENCES["translation_confirmed"]
    }.freeze

    # Which actions are listed: purges and a block's deletion leave no
    # subject to link to, so they aren't here.
    ACTIONS = {
      "page" => %w[created updated published unpublished scheduled moved trashed restored translation_confirmed],
      "post" => %w[created updated published unpublished scheduled trashed restored translation_confirmed],
      "media" => %w[uploaded updated trashed restored translation_confirmed],
      "block" => BLOCK_SENTENCES.keys
    }.flat_map { |prefix, verbs| verbs.map { |verb| "#{prefix}.#{verb}" } }.freeze

    # `sentence_parts` is `[before, record, after]`: "<actor_name> <before>
    # “<record title>”<after>". `at` is when the (first) change happened and
    # `span_end` when the coalesced burst last extended (nil for a single
    # moment). `record` is the page, post or image the sentence is about
    # (a block's owner).
    Row = Data.define(:event, :record, :sentence_parts, :actor_name, :via_token, :at, :span_end)

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
      events = Audit::Event.where(action: ACTIONS).order(last_occurred_at: :desc, id: :desc).limit(@limit * OVERFETCH).to_a
      return [] if events.empty?

      records = readable_records(events)
      ActiveRecord::Associations::Preloader.new(records: events, associations: :user).call
      events.filter_map { |event| row_for(event, records) }.first(@limit)
    end

    def row_for(event, records)
      prefix, verb = event.action.split(".", 2)
      subject = subject_key(event, records)
      record = records[subject]
      return unless record

      parts = (prefix == "block" ? BLOCK_SENTENCES : SENTENCES).fetch(verb)
      before, after = parts
      after = "#{after} for #{scheduled_for(event, record)}" if event.action.end_with?(".scheduled")
      Row.new(event:, record:, sentence_parts: [ before, record, after ], actor_name: Admin::UserNameComponent.new(user: event.user, user_id: event.user_id).label,
        via_token: event.actor_type == "ApiToken", at: event.occurred_at,
        span_end: (event.last_occurred_at if event.last_occurred_at > event.occurred_at))
    end

    # "6 Oct": the date the event scheduled it for, read from the event
    # itself (the record may have been rescheduled since); the record's own
    # `published_at` when the event doesn't carry one.
    def scheduled_for(event, record)
      value = Array(event.field_changes&.dig("published_at")).last
      time = (value.present? ? Time.zone.parse(value.to_s) : nil) || record.published_at
      time&.in_time_zone&.strftime("%-d %b")
    end

    # Where an event's sentence points: `[class name, id]` of the page, post
    # or image. A block's event reaches its owner through `@blocks`;
    # `block.reordered` already names the page as its subject.
    def subject_key(event, records)
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
