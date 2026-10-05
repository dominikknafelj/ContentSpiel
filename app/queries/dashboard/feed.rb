module Dashboard
  # The two *personal* lists on the CS Studio dashboard -- "Your drafts" and
  # "Going live next" (design pass round 2, Task 16) -- read-scoped through
  # `AccessControl.scope` (which already hides trashed records) and built in
  # a constant number of queries, whatever the data size: one limited query
  # per model per list (pages and posts), merged and cut to the list's limit
  # in Ruby. (The "Recent activity" feed is `Dashboard::Activity`; the
  # "Needs translation" numbers come from `Translations::StateIndex`.)
  #
  # "Mine" (spec §4.2): a post I authored, or any page/post whose *newest*
  # audit event is mine. Pages have no author, so for a page only the last
  # change counts -- someone editing it after me takes it off my drafts.
  # "Me" is the human: an event's `user_id`, which `Audit.record` fills for
  # a user and for any of their API tokens alike, so a change made through
  # MCP is still mine.
  #
  # The newest event is decided in SQL, per row, through a LATERAL subquery
  # (`#with_newest_event`) rather than by loading candidates and checking
  # them in Ruby: a filter applied before the LIMIT can't under-fill a list
  # the way "load 3x the limit, then drop what isn't mine" can, and it keeps
  # each list to exactly one query per model however many records exist.
  # "Going live next" is site-wide, but joins the same subquery so it can
  # say "by you" without a query per row (`#mine?`).
  class Feed
    LIMITS = { drafts: 5, going_live_next: 5 }.freeze

    # Events that never count as "the newest change" (final fix wave, I1):
    # `ApplicationService#denied` records `access.denied` with the refused
    # record as its subject -- and it coalesces -- so without this a user
    # merely *refused* on someone else's page would take it over as "mine".
    # The LATERAL join excludes exactly this list. (`Dashboard::Activity`
    # never lists the action either: it only lists content events.)
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

    def going_live_next
      @going_live_next ||= page_and_post_relations { |r| scheduled_soonest_first(r) }
        .flat_map do |relation|
          # The limit is taken on the ids first, so the LATERAL "newest
          # event" lookup runs for at most LIMIT rows, not for every
          # scheduled record before the cut.
          soonest = relation.select("#{relation.quoted_table_name}.id").limit(LIMITS[:going_live_next])
          outer = relation.klass.where(id: soonest).reorder(published_at: :asc, id: :asc)
          with_newest_event(outer, join: "LEFT JOIN")
            .select("#{outer.quoted_table_name}.*, newest.newest_user_id AS dashboard_newest_user_id").to_a
        end
        .then { |records| soonest_first(records, :published_at, LIMITS[:going_live_next]) }
    end

    # Whether a record `#going_live_next` returned is mine (a post I wrote,
    # or one whose newest change is mine) -- the card's "by you".
    def mine?(record)
      return false unless @user

      record.try(:dashboard_newest_user_id) == @user.id || (record.is_a?(Post) && record.author_id == @user.id)
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

    # Scheduled (spec §10.4 of the CMS spec: a future `published_at`),
    # soonest first.
    def scheduled_soonest_first(relation)
      relation.scheduled.reorder(published_at: :asc, id: :asc)
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
    # both stay index lookups.
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
  end
end
