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
  # (`#with_newest_event`, named `newest`) rather than by loading candidates and checking
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
    # never lists the action either: it only lists content events.) A note's
    # events have the page, post or block as their subject too, and are no
    # change to it either (notes spec §3.5): "Mine" and "Changed by"
    # (`Audit::ChangeSince` reads this list) ignore them.
    NOT_A_CHANGE = (%w[access.denied page.taken_over post.taken_over block.taken_over] + Audit::Sentence::NOTE_VERBS.keys).freeze

    # The LATERAL subquery `#with_newest_event` joins, as a table to read its
    # columns from: `newest.newest_user_id`, `newest.newest_at`.
    NEWEST = Arel::Table.new("newest")

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
          soonest = relation.select(:id).limit(LIMITS[:going_live_next])
          outer = relation.klass.where(id: soonest).reorder(published_at: :asc, id: :asc)
          with_newest_event(outer).select(outer.arel_table[Arel.star], NEWEST[:newest_user_id].as("dashboard_newest_user_id")).to_a
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
    # to the same limit). The join is a LEFT JOIN, so an authored post with no
    # event at all still counts.
    def mine(relations, limit:)
      return [] unless @user

      relations.flat_map do |relation|
        mine = NEWEST[:newest_user_id].eq(@user.id)
        mine = mine.or(relation.arel_table[:author_id].eq(@user.id)) if relation.klass <= Post
        with_newest_event(relation).where(mine).limit(limit).to_a
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
    #
    # The two halves are relations (`#newest_own_event`, `#newest_block_event`)
    # that refer to the outer row's id; what Active Record has no syntax for --
    # the UNION ALL, the derived table and the LATERAL join -- is Arel:
    #
    #   LEFT OUTER JOIN LATERAL (
    #     SELECT c.user_id AS newest_user_id, c.last_occurred_at AS newest_at
    #     FROM ( (<own newest>) UNION ALL (<newest about a block>) ) c
    #     ORDER BY c.last_occurred_at DESC, c.id DESC LIMIT 1
    #   ) newest ON TRUE
    def with_newest_event(relation)
      model = relation.klass
      own = newest_own_event(model).arel
      candidates = block_owner?(model) ? Arel::Nodes::TableAlias.new(own.union(:all, newest_block_event(model).arel), "c") : own.as("c")
      c = Arel::Table.new("c")
      newest = Arel::SelectManager.new(candidates)
        .project(c[:user_id].as("newest_user_id"), c[:last_occurred_at].as("newest_at"))
        .order(c[:last_occurred_at].desc, c[:id].desc).take(1)
      relation.joins(model.arel_table.join(newest.lateral("newest"), Arel::Nodes::OuterJoin).on(Arel::Nodes::True.new).join_sources)
    end

    # The newest event about the outer row itself (`user_id, last_occurred_at,
    # id`, one row).
    def newest_own_event(model)
      events = Audit::Event.arel_table
      newest_of(Audit::Event.where(subject_type: subject_type_names(model)).where(events[:subject_id].eq(model.arel_table[:id])))
    end

    # The newest event about any block the outer row owns: `content_blocks
    # INNER JOIN audit_events ON subject_type IN (<block types>) AND
    # subject_id = content_blocks.id`, a join on a polymorphic pair no
    # association describes.
    def newest_block_event(model)
      events, blocks = Audit::Event.arel_table, ContentBlock.arel_table
      about_block = events[:subject_type].in(subject_type_names(ContentBlock)).and(events[:subject_id].eq(blocks[:id]))
      owned = ContentBlock.joins(blocks.join(events).on(about_block).join_sources)
        .where(owner_type: model.base_class.name).where(blocks[:owner_id].eq(model.arel_table[:id]))
      newest_of(owned)
    end

    # The newest change among the events `relation` reaches: one row of
    # `user_id, last_occurred_at, id`, `NOT_A_CHANGE` left out.
    def newest_of(relation)
      events = Audit::Event.arel_table
      relation.merge(Audit::Event.where.not(action: NOT_A_CHANGE).order(last_occurred_at: :desc, id: :desc))
        .select(events[:user_id], events[:last_occurred_at], events[:id]).limit(1)
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
