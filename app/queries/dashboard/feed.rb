module Dashboard
  # Every list on the CS Studio dashboard (dashboard spec §4), read-scoped
  # through `AccessControl.scope` -- which already hides trashed records --
  # and built in a constant number of queries, whatever the data size: one
  # limited query per model per list (pages, posts and, for a `media.upload`
  # holder, images -- merged and cut to the list's limit in Ruby), then ONE
  # batched "newest audit event per record" query for every row any list
  # returned (`#last_change`), plus one actor preload per actor type.
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

    # `{ actor:, at: }` from `record`'s newest audit event -- `actor` nil for
    # a change made by the system (a nil actor on a trusted channel) or by
    # an actor since deleted -- or nil when `record` has no event at all.
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
    # kept images.
    def all_relations
      relations = page_and_post_relations(&:itself)
      relations << Media::Asset.kept if AccessControl.holds?(@actor, "media.upload", channel: @channel)
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
    # `newest.newest_at`): one index lookup on `(subject_type, subject_id)`
    # per row, never more than one event row per record.
    def with_newest_event(relation, join: "JOIN")
      sql = <<~SQL.squish
        #{join} LATERAL (
          SELECT e.user_id AS newest_user_id, e.last_occurred_at AS newest_at
          FROM audit_events e
          WHERE e.subject_type IN (?) AND e.subject_id = #{relation.quoted_table_name}.id
          ORDER BY e.last_occurred_at DESC, e.id DESC
          LIMIT 1
        ) newest ON true
      SQL
      relation.joins(ActiveRecord::Base.sanitize_sql_array([ sql, subject_type_names(relation.klass) ]))
    end

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
    # the lists' own limits, then one actor preload per actor type. A record
    # with events under both its current and a legacy subject type comes
    # back twice (DISTINCT ON sees two types); the newer of the two wins.
    def load_last_changes
      records = [ drafts, scheduled, recently_edited, going_live_next, recently_updated ].flatten.uniq
      return {} if records.empty?

      events = records.group_by { |r| r.class.base_class }
        .map { |model, rs| Audit::Event.where(subject_type: subject_type_names(model), subject_id: rs.map(&:id)) }
        .reduce(:or)
        .select("DISTINCT ON (subject_type, subject_id) audit_events.*")
        .order(:subject_type, :subject_id, last_occurred_at: :desc, id: :desc)
        .to_a
      ActiveRecord::Associations::Preloader.new(records: events, associations: :actor).call

      events.group_by { |e| [ Audit::Event::LEGACY_POLYMORPHIC_TYPES.fetch(e.subject_type, e.subject_type), e.subject_id ] }
        .transform_values { |es| es.max_by { |e| [ e.last_occurred_at, e.id ] }.then { |e| { actor: e.actor, at: e.last_occurred_at } } }
    end
  end
end
