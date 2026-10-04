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
  # A change made through an API token is shown as its *user's* (the event's
  # `user_id`, filled for a user and a token alike), carrying `via_label`
  # (the token's name as recorded on the event, `Audit::Event#via_label`);
  # the token itself is never loaded.
  class Activity
    # How far back the feed looks: the scan bound for a large audit table.
    WINDOW = 90.days

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
      "page" => %w[created updated published unpublished moved trashed restored translation_confirmed],
      "post" => %w[created updated published unpublished scheduled trashed restored translation_confirmed],
      "media" => %w[uploaded updated trashed restored translation_confirmed],
      "block" => BLOCK_SENTENCES.keys
    }.flat_map { |prefix, verbs| verbs.map { |verb| "#{prefix}.#{verb}" } }.freeze

    # `sentence_parts` is `[before, record, after]`: "<actor_name> <before>
    # “<record title>”<after>". `at` is when the (first) change happened and
    # `span_end` when the coalesced burst last extended (nil for a single
    # moment). `record` is the page, post or image the sentence is about
    # (a block's owner).
    Row = Data.define(:event, :record, :sentence_parts, :actor_name, :via_label, :at, :span_end)

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
      condition = readable_subjects_sql
      return [] unless condition # nothing readable: no query at all

      events = Audit::Event.where(action: ACTIONS).where(last_occurred_at: WINDOW.ago..)
        .where(condition).order(last_occurred_at: :desc, id: :desc).limit(@limit).to_a
      return [] if events.empty?

      records = readable_records(events)
      ActiveRecord::Associations::Preloader.new(records: events, associations: :user).call
      events.filter_map { |event| row_for(event, records) }
    end

    # The SQL condition on an event's subject (see the class comment); nil
    # for a viewer who can read nothing.
    def readable_subjects_sql
      pages = readable_ids(Page, "pages.read")
      posts = readable_ids(Post, "posts.read")
      branches = []
      branches << "(audit_events.subject_type = 'Page' AND audit_events.subject_id IN (#{pages}))" if pages
      branches << "(audit_events.subject_type = 'Post' AND audit_events.subject_id IN (#{posts}))" if posts
      owners = []
      owners << "(owner_type = 'Page' AND owner_id IN (#{pages}))" if pages
      owners << "(owner_type = 'Post' AND owner_id IN (#{posts}))" if posts
      if owners.any?
        branches << "(audit_events.subject_type = 'ContentBlock' AND audit_events.subject_id IN " \
                    "(SELECT id FROM content_blocks WHERE #{owners.join(' OR ')}))"
      end
      if AccessControl.holds?(@actor, "media.upload", channel: @channel)
        types = ([ "Media::Asset" ] + Audit::Event::LEGACY_POLYMORPHIC_TYPES.keys).map { |t| ActiveRecord::Base.connection.quote(t) }.join(", ")
        branches << "(audit_events.subject_type IN (#{types}) AND audit_events.subject_id IN " \
                    "(SELECT id FROM #{Media::Asset.quoted_table_name} WHERE trashed_at IS NULL))"
      end
      branches.any? ? "(#{branches.join(' OR ')})" : nil
    end

    # `SELECT id` SQL of the records of `model` the viewer may read, or nil
    # when they hold no such right at all (so no subquery is built).
    def readable_ids(model, key)
      return unless AccessControl.holds?(@actor, key, channel: @channel)

      AccessControl.scope(@actor, key, model.all, channel: @channel).unscope(:order).select("#{model.quoted_table_name}.id").to_sql
    end

    def row_for(event, records)
      prefix, verb = event.action.split(".", 2)
      subject = subject_key(event, records)
      record = records[subject]
      return unless record

      # Only a page or post can be scheduled: `BLOCK_SENTENCES` (and an image's
      # wording) have no "scheduled", and a block event whose only change was a
      # `published_at` would otherwise be a KeyError on the landing page.
      verb = "scheduled" if verb == "updated" && %w[page post].include?(prefix) && scheduled_only?(event)
      before, after = (prefix == "block" ? BLOCK_SENTENCES : SENTENCES).fetch(verb)
      if verb == "scheduled" && (date = scheduled_for(event, record))
        after = "#{after} for #{date}"
      end
      Row.new(event:, record:, sentence_parts: [ before, record, after ], actor_name: Admin::UserNameComponent.new(user: event.user, user_id: event.user_id).label,
        via_label: event.via_label, at: event.occurred_at,
        span_end: (event.last_occurred_at if event.last_occurred_at > event.occurred_at))
    end

    # An `*.updated` whose only change is a `published_at` in the future is
    # a scheduling (the services record `*.scheduled` themselves, but an
    # older or hand-written event may not).
    def scheduled_only?(event)
      changes = event.field_changes
      changes.is_a?(Hash) && changes.keys == [ "published_at" ] && (time = parse_time(Array(changes["published_at"]).last)) && time > event.occurred_at
    end

    # "6 Oct": the date the event scheduled it for, read from the event
    # itself (the record may have been rescheduled since); the record's own
    # `published_at` when the event carries none or a malformed one (a bad
    # stored value must never 500 the landing page); nil -- no " for ..."
    # at all -- when neither gives a date.
    def scheduled_for(event, record)
      time = parse_time(Array(event.field_changes.is_a?(Hash) ? event.field_changes["published_at"] : nil).last) || record.published_at
      time&.in_time_zone&.strftime("%-d %b")
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError, RangeError
      nil
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
