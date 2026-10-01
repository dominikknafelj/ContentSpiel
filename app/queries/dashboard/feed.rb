module Dashboard
  # Every list on the CS Studio dashboard (dashboard spec §4), read-scoped
  # through `AccessControl.scope` -- which already hides trashed records --
  # and built in a constant number of queries, whatever the data size: one
  # limited query per model per list (pages, posts and, for a `media.upload`
  # holder, images -- merged and cut to the list's limit in Ruby), then ONE
  # batched "newest audit event per record" query for every row any list
  # returned (`#last_change`), plus one actor preload per actor type and
  # one preload of those events' users.
  #
  # "Mine" (spec §4.2): a post I authored, or any page/post/image whose
  # *newest* audit event is mine. Pages have no author, so for a page only
  # the last change counts -- someone editing it after me takes it off my
  # lists (but not off the site's "Recently updated"). "Me" is the human:
  # an event's `user_id`, which `Audit.record` fills for a user and for any
  # of their API tokens alike, so a change made through MCP is still mine.
  #
  # The newest event is decided in SQL, per row, through a LATERAL subquery
  # (`#with_newest_event`) rather than by loading candidates and checking
  # them in Ruby: a filter applied before the LIMIT can't under-fill a list
  # the way "load 3x the limit, then drop what isn't mine" can, and it keeps
  # each list to exactly one query per model however many records exist.
  # "Recently edited by you" is the same join, ordered by that event's time.
  class Feed
    LIMITS = { drafts: 10, scheduled: 10, recently_edited: 10, going_live_next: 10, recently_updated: 15 }.freeze

    # Events that never count as "the newest change" (final fix wave, I1):
    # `ApplicationService#denied` records `access.denied` with the refused
    # record as its subject -- and it coalesces -- so without this a user
    # merely *refused* on someone else's page would take it over as "mine"
    # and become its "by". Both places that decide the newest event (the
    # LATERAL join and `#load_last_changes`) exclude exactly this list, so
    # a row's "mine" and its "by" can never disagree.
    NOT_A_CHANGE = %w[access.denied].freeze

    # `channel:` is captured here rather than read from `Current` each time
    # a list is first asked for: the lists are lazy, and a view may well
    # render them outside the block that set the request's channel.
    def initialize(actor:, channel: Current.channel)
      @actor = actor
      @channel = channel
      @user = actor.is_a?(ApiToken) ? actor.user : actor
    end

    def drafts
      @drafts ||= mine(page_and_post_relations { |r| r.where(published_at: nil).reorder(updated_at: :desc, id: :desc) }, limit: LIMITS[:drafts])
        .then { |records| newest_first(records, :updated_at, LIMITS[:drafts]) }
    end

    def scheduled
      @scheduled ||= mine(page_and_post_relations { |r| scheduled_soonest_first(r) }, limit: LIMITS[:scheduled])
        .then { |records| soonest_first(records, :published_at, LIMITS[:scheduled]) }
    end

    def going_live_next
      @going_live_next ||= page_and_post_relations { |r| scheduled_soonest_first(r) }
        .flat_map { |r| r.limit(LIMITS[:going_live_next]).to_a }
        .then { |records| soonest_first(records, :published_at, LIMITS[:going_live_next]) }
    end

    def recently_updated
      @recently_updated ||= all_relations
        .flat_map { |r| r.reorder(updated_at: :desc, id: :desc).limit(LIMITS[:recently_updated]).to_a }
        .then { |records| newest_first(records, :updated_at, LIMITS[:recently_updated]) }
    end

    # The pages, posts and images whose newest audit event is mine, by that
    # event's time (`last_occurred_at`, so a coalesced autosave session
    # counts from its latest save), newest first.
    def recently_edited
      @recently_edited ||= begin
        limit = LIMITS[:recently_edited]
        all_relations.flat_map do |relation|
          next [] unless @user

          table = relation.quoted_table_name
          with_newest_event(relation)
            .where("newest.newest_user_id = ?", @user.id)
            .select("#{table}.*, newest.newest_at AS dashboard_edited_at")
            .reorder("newest.newest_at DESC, #{table}.id DESC")
            .limit(limit).to_a
        end.then { |records| newest_first(records, :dashboard_edited_at, limit) }
      end
    end

    # `{ actor:, user:, at: }` from `record`'s newest audit event -- `actor`
    # nil for a change made by the system (a nil actor on a trusted channel)
    # or by an actor since deleted; `user` the human behind it (the actor
    # itself for a user, the token's owner for an API token -- `Audit.record`
    # fills `user_id` for both), so a change made through MCP can be shown
    # as its user's without a query per row -- or nil when `record` has no
    # event at all.
    # The first call loads every listed record's newest event in one query
    # (so it forces every list); a record no list returned answers nil.
    def last_change(record)
      @last_changes ||= load_last_changes
      @last_changes[[ record.class.base_class.name, record.id ]]
    end

    private

    # Pages and posts the actor may read, each narrowed by the block (one
    # relation per model, never loaded here).
    def page_and_post_relations(&narrow)
      [
        AccessControl.scope(@actor, "pages.read", Page.all, channel: @channel),
        AccessControl.scope(@actor, "posts.read", Post.all, channel: @channel)
      ].map(&narrow)
    end

    # Pages, posts and -- only for a `media.upload` holder (spec §4.4: the
    # library isn't read-scoped, so holding the right is the whole check) --
    # kept images, loaded `with_variants` so each row's thumbnail
    # (`Media::Asset#thumbnail_url`, which reads the attachment, its blob
    # and the blob's variant records) costs a constant three preload
    # queries per list instead of three per image.
    def all_relations
      relations = page_and_post_relations(&:itself)
      relations << Media::Asset.kept.with_variants if AccessControl.holds?(@actor, "media.upload", channel: @channel)
      relations
    end

    # Scheduled (spec §10.4 of the CMS spec: a future `published_at`),
    # soonest first.
    def scheduled_soonest_first(relation)
      relation.where("#{relation.quoted_table_name}.published_at > ?", Time.current).reorder(published_at: :asc, id: :asc)
    end

    # Each (already ordered) relation narrowed to my records -- a post I
    # authored, or a record whose newest event is mine -- and loaded, at
    # most `limit` per relation (the caller sorts and cuts the merged set
    # to the same limit). LEFT JOIN, so an authored post with no event at all
    # still counts.
    def mine(relations, limit:)
      return [] unless @user

      relations.flat_map do |relation|
        table = relation.quoted_table_name
        condition = +"newest.newest_user_id = :user"
        condition << " OR #{table}.author_id = :user" if relation.klass <= Post
        with_newest_event(relation, join: "LEFT JOIN")
          .where(condition, user: @user.id)
          .limit(limit).to_a
      end
    end

    # Joins each row to its newest audit event (`newest.newest_user_id`,
    # `newest.newest_at`): never more than one event row per record, found
    # through the `(subject_type, subject_id, last_occurred_at)` index.
    #
    # For a block owner (a page or post) the newest event is the newer of
    # two: its own newest, and the newest about any block it currently owns
    # (final fix wave, I3 -- a block event's subject is the block, but
    # editing a block is editing its page, so it counts towards "mine" and
    # "by" exactly like a title edit). Each half is its own `LIMIT 1`, so
    # both stay index lookups; `#load_last_changes` applies the same rule.
    # An event about a block deleted since can't be traced back to its owner
    # any more (the block row is gone) -- its edit still shows through the
    # owner's `updated_at`, which `ContentBlocks::Destroy` bumps.
    def with_newest_event(relation, join: "JOIN")
      table = relation.quoted_table_name
      own = <<~SQL.squish
        SELECT e.user_id, e.last_occurred_at, e.id
        FROM audit_events e
        WHERE e.subject_type IN (:types) AND e.subject_id = #{table}.id AND e.action NOT IN (:ignored)
        ORDER BY e.last_occurred_at DESC, e.id DESC
        LIMIT 1
      SQL
      candidates = if block_owner?(relation.klass)
        <<~SQL.squish
          (#{own})
          UNION ALL
          (SELECT e.user_id, e.last_occurred_at, e.id
           FROM content_blocks b
           JOIN audit_events e ON e.subject_type IN (:block_types) AND e.subject_id = b.id
           WHERE b.owner_type = :owner_type AND b.owner_id = #{table}.id AND e.action NOT IN (:ignored)
           ORDER BY e.last_occurred_at DESC, e.id DESC
           LIMIT 1)
        SQL
      else
        own
      end
      sql = <<~SQL.squish
        #{join} LATERAL (
          SELECT c.user_id AS newest_user_id, c.last_occurred_at AS newest_at
          FROM (#{candidates}) c
          ORDER BY c.last_occurred_at DESC, c.id DESC
          LIMIT 1
        ) newest ON true
      SQL
      relation.joins(ActiveRecord::Base.sanitize_sql_array([ sql, {
        types: subject_type_names(relation.klass), block_types: subject_type_names(ContentBlock),
        owner_type: relation.klass.base_class.name, ignored: NOT_A_CHANGE
      } ]))
    end

    def block_owner?(model) = AccessControl::Checker::BLOCK_OWNER_PREFIX.key?(model.base_class.name)

    # Every `subject_type` an event about `model` may carry: its current
    # name plus any name it was recorded under before a rename -- the
    # append-only log keeps e.g. "MediaAsset" rows forever
    # (`Audit::Event::LEGACY_POLYMORPHIC_TYPES`).
    def subject_type_names(model)
      name = model.base_class.name
      [ name, *Audit::Event::LEGACY_POLYMORPHIC_TYPES.filter_map { |old, current| old if current == name } ]
    end

    def newest_first(records, attribute, limit) = records.max_by(limit) { |r| [ r.public_send(attribute), r.id ] }

    def soonest_first(records, attribute, limit) = records.min_by(limit) { |r| [ r.public_send(attribute), r.id ] }

    # One DISTINCT ON query over every listed record (spec §4.5), bounded by
    # the lists' own limits, then one actor preload per actor type and one
    # of their users. Its candidates are each record's own events plus, for
    # a page or post, its current blocks' events (the same rule as
    # `#with_newest_event`), every one tagged with the record it counts for
    # (`dashboard_owner_type`/`_id`) -- the model's current name, so a
    # legacy subject type ("MediaAsset") lands on the same record too.
    def load_last_changes
      records = [ drafts, scheduled, recently_edited, going_live_next, recently_updated ].flatten.uniq
      return {} if records.empty?

      candidates = records.group_by { |r| r.class.base_class }.flat_map do |model, rs|
        owner = Audit::Event.connection.quote(model.name)
        ids = rs.map(&:id)
        own = Audit::Event.where(subject_type: subject_type_names(model), subject_id: ids)
          .select("audit_events.*, #{owner} AS dashboard_owner_type, audit_events.subject_id AS dashboard_owner_id")
        next [ own ] unless block_owner?(model)

        via_blocks = Audit::Event.joins("JOIN content_blocks ON content_blocks.id = audit_events.subject_id")
          .where(subject_type: subject_type_names(ContentBlock), content_blocks: { owner_type: model.name, owner_id: ids })
          .select("audit_events.*, #{owner} AS dashboard_owner_type, content_blocks.owner_id AS dashboard_owner_id")
        [ own, via_blocks ]
      end
      union = candidates.map { |relation| "(#{relation.where.not(action: NOT_A_CHANGE).to_sql})" }.join(" UNION ALL ")

      events = Audit::Event.from("(#{union}) audit_events")
        .select("DISTINCT ON (dashboard_owner_type, dashboard_owner_id) audit_events.*")
        .order(:dashboard_owner_type, :dashboard_owner_id, last_occurred_at: :desc, id: :desc)
        .to_a
      ActiveRecord::Associations::Preloader.new(records: events, associations: %i[actor user]).call

      events.to_h do |e|
        [ [ e.dashboard_owner_type, e.dashboard_owner_id ], { actor: e.actor, user: e.user, user_id: e.user_id, at: e.last_occurred_at } ]
      end
    end
  end
end
