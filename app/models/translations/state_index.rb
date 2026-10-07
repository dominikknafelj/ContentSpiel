module Translations
  # The stored form of `Translations::Status`: one `translation_states` row
  # per page, post, library image and the site settings, per target
  # language, so a list can `WHERE`, `COUNT` and page on where things stand
  # instead of working every record's state out in Ruby (the translations
  # overview used to walk the whole site per request; the page tree and the
  # posts list used a cache keyed on everything a state is computed from).
  #
  # Derived data, like `public_paths` (`PublicSite::Paths`) and
  # `media_usages` (`Media::UsageIndex`): never written by hand, kept
  # current by the services that change what a state is computed from -- the
  # save services (and a block's save/destroy, which refreshes its *owner*,
  # since blocks roll up into their page or post), `Translations::Confirm`,
  # `Trash::Purge` (`remove`) and the language services (`rebuild_all`) --
  # and rebuilt by `bin/rails translations:reindex` whenever it is suspected
  # stale (a bug, a direct SQL edit, a restored backup).
  # `test/services/translation_state_parity_test.rb` is the guard against a
  # write path that forgets it.
  #
  # Every write is called inside the service's own transaction, so a rolled
  # back save leaves the rows untouched. A trashed record keeps its rows
  # (its state doesn't change in the trash, and a restore needs no work);
  # the readers' scopes already hide trashed records.
  #
  # A record with no row reads `:complete`: a stale-but-absent row must never
  # flag work that nobody can find, and an image or page created outside the
  # services (a console `create`, a test) simply isn't listed until it's next
  # saved or reindexed.
  module StateIndex
    module_function

    BATCH_SIZE = 200

    # Recomputes the record's rows. A ContentBlock refreshes its owner; an
    # owner that is gone (or never saved) has nothing to hold rows for.
    def refresh(record)
      owner = record.is_a?(ContentBlock) ? record.owner : record
      return if owner.nil? || owner.new_record?
      return remove(owner) if owner.destroyed?

      write([ owner ])
      State.where(record_type: owner.class.polymorphic_name, record_id: owner.id)
        .where.not(locale: Translations.target_locales).delete_all
    end

    # The record's rows, for good (`Trash::Purge`).
    def remove(record)
      State.where(record_type: record.class.polymorphic_name, record_id: record.id).delete_all
    end

    # Every row from scratch: kept and trashed pages, posts and images in
    # batches, the site settings row, then rows whose record no longer
    # exists. Synchronous and proportional to the site's size -- fine while
    # sites are small, and the natural thing to move into a job later.
    def rebuild_all
      [ Page, Post, Media::Asset ].each do |model|
        model.find_in_batches(batch_size: BATCH_SIZE) { |batch| write(batch) }
        orphans = State.where(record_type: model.polymorphic_name).where.not(record_id: model.select(:id))
        orphans.delete_all
      end
      write([ SiteSetting.first ].compact)
      State.where.not(record_type: [ Page, Post, Media::Asset, SiteSetting ].map(&:polymorphic_name)).delete_all
      State.where.not(locale: Translations.target_locales).delete_all
    end

    # `{ record => { locale => Symbol } }` in one query; a record (or a
    # locale) with no row reads `:complete`.
    def states_for(records, locales: Translations.target_locales)
      rows = rows_for(records, locales)
      locales = locales.map(&:to_s)
      Array(records).index_with do |record|
        locales.index_with { |code| (rows.dig(key(record), code)&.state || "complete").to_sym }
      end
    end

    # `{ record => { locale => { missing:, outdated: } } }` in one query.
    def counts_for(records, locales: Translations.target_locales)
      rows = rows_for(records, locales)
      locales = locales.map(&:to_s)
      Array(records).index_with do |record|
        locales.index_with do |code|
          row = rows.dig(key(record), code)
          { missing: row&.missing_count || 0, outdated: row&.outdated_count || 0 }
        end
      end
    end

    # The number of records that actually hold a stored translation today
    # (the Default-language dialog's "(N items)", decision D8): a non-empty
    # `translation_sources` -- some field with an entry for some language, which
    # is what the Tracker writes when a target-language value is saved and
    # removes when it is blanked. NOT "has a non-`missing` state row": an image
    # without alt text, or a page with nothing to translate, reads `complete`
    # while holding nothing. A page's or post's blocks roll into it, as in the
    # index (a page whose only translation is in a block counts once). Kept
    # pages, posts and images only; the settings row has no trash. One query:
    # `SELECT (SELECT COUNT(*) ...) + (SELECT COUNT(*) ...) + ...`.
    def translated_record_count
      parts = [ Page, Post ].map do |model|
        blocks = ContentBlock.where(owner_type: model.polymorphic_name)
          .where(ContentBlock.arel_table[:owner_id].eq(model.arel_table[:id])).where(holds_translation(ContentBlock))
        model.kept.where(holds_translation(model).or(SqlNodes.exists(blocks.select(1))))
      end
      parts << Media::Asset.kept.where(holds_translation(Media::Asset))
      parts << SiteSetting.where(holds_translation(SiteSetting))
      counts = parts.map { |relation| Arel::Nodes::Grouping.new(relation.select(Arel.star.count).arel.ast) }
      # sql: no string here -- a SELECT with no table has no relation to run it, so the Arel statement goes to the connection
      State.connection.select_value(Arel::SelectManager.new.project(counts.reduce(:+))).to_i
    end

    # `jsonb_path_exists(translation_sources, '$.*.*')`: some field has an
    # entry for some language.
    def holds_translation(model) = SqlNodes.function("jsonb_path_exists", model.arel_table[:translation_sources], "$.*.*")

    # `relation` (pages, posts or images) narrowed to the records whose state
    # in `locale` is one of `states` (Strings; `complete` includes a record
    # with no row). A join, so it composes with the caller's own
    # `where`, `order`, `limit` and `count`.
    #
    # When `states` leaves out `complete` no record without a row can match,
    # so the join is an INNER JOIN on the filter: `COALESCE(...)` is not
    # strict, so Postgres can't turn the LEFT JOIN into an inner one itself,
    # and a "newest outdated item" lookup in a language where nothing is
    # outdated would read every readable record before returning nothing.
    def joins(relation, locale:, states:)
      states = Array(states).map(&:to_s)
      if states.include?("complete")
        relation.joins(state_join(relation.klass, locale.to_s, Arel::Nodes::OuterJoin))
          .where(SqlNodes.coalesce(State.arel_table[:state], "complete").in(states))
      else
        relation.joins(state_join(relation.klass, locale.to_s, Arel::Nodes::InnerJoin)).merge(State.where(state: states))
      end
    end

    # `{ total:, complete:, missing:, outdated: }` over the given (already
    # read-scoped) relations: items, not fields. One language's entry of
    # `summaries`.
    def summary(locale, relations)
      summaries([ locale ], relations).fetch(locale.to_s).slice(:total, :complete, :missing, :outdated)
    end

    # `{ locale => { total:, complete:, missing:, outdated: } }` for every
    # given language over the (already read-scoped) relations, items not
    # fields -- the same numbers as `summary`, but in two grouped queries per
    # relation however many languages there are (the translations matrix's
    # summary cards). `complete` is what is left of the total, so a record
    # with no row for a language reads complete, as everywhere else.
    def summaries(locales, relations)
      locales = locales.map(&:to_s)
      result = locales.index_with { { total: 0, missing: 0, outdated: 0 } }
      Array(relations).each do |relation|
        base = relation.unscope(:order)
        total = base.count
        result.each_value { |counts| counts[:total] += total }
        base.joins(state_join(relation.klass, locales, Arel::Nodes::InnerJoin)).merge(State.where(state: %w[missing outdated]))
          .group(State.arel_table[:locale], State.arel_table[:state]).count
          .each { |(locale, state), count| result.fetch(locale)[state.to_sym] += count }
      end
      result.transform_values { |counts| counts.merge(complete: counts[:total] - counts[:missing] - counts[:outdated]) }
    end

    # "This record is in one of `states` in any of `locales`" as a condition (an
    # Arel node, despite the name it has kept) for a `where`, a `where.not`, a
    # `SELECT` list or a `FILTER` over `model`'s table: an
    # EXISTS rather than `joins`, which narrows by one language. The posts
    # list's Translation filter and the translations matrix both ask about a
    # record as a whole this way; a record with no row never matches.
    def exists_in_any_locale_sql(model, states:, locales:)
      rows = State.where(record_type: model.polymorphic_name, locale: Array(locales).map(&:to_s), state: Array(states).map(&:to_s))
        .where(State.arel_table[:record_id].eq(model.arel_table[:id]))
      SqlNodes.exists(rows)
    end

    # Matches what `Time#iso8601` writes into `translation_original_changed_at`
    # (`Translations::Tracker#record_original_changes`), with or without a
    # zone offset (the site time zone applies while an editor saves), and
    # nothing else: only a value like this is cast, so one malformed stored
    # value can never raise a cast error and 500 the screen. "Like this"
    # includes being a REAL date: a day that doesn't exist in its month
    # (2026-02-31, 2026-02-29, 2026-04-31) passes a shape-only check and then
    # fails the `::timestamptz` cast ("date/time field value out of range"),
    # so the month lengths and the leap-year rule are spelled out, and year
    # 0000 (which Postgres has no such date for) is refused.
    ISO_DATE = "(?!0000)(\\d{4}-(0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])" \
      "|\\d{4}-(0[469]|11)-(0[1-9]|[12]\\d|30)" \
      "|\\d{4}-02-(0[1-9]|1\\d|2[0-8])" \
      "|(\\d\\d(0[48]|[2468][048]|[13579][26])|([02468][048]|[13579][26])00)-02-29)".freeze
    # The UTC offset is capped at +-15:59: Postgres refuses a displacement of
    # 16:00 or more ("time zone displacement out of range").
    ISO_TIMESTAMP = "^#{ISO_DATE}T([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(\\.\\d+)?(Z|[+-](0\\d|1[0-5]):[0-5]\\d)$".freeze

    # When this record's original text last changed (an Arel expression, despite
    # the name it has kept), "the most
    # recently changed original" the translations matrix sorts by: the
    # greatest of the stamps in the record's own `translation_original_changed_at`
    # (any tracked field) and, for a page or post, of its blocks' stamps (a
    # block's original changing is the page's original changing; one
    # correlated aggregate over the `owner_type, owner_id` index), falling
    # back to `updated_at` for a record that predates the stamps. A save that
    # changes only a translation, or a Confirm, moves none of it.
    #
    #   COALESCE(GREATEST(<newest own stamp>, <newest stamp of its blocks>), updated_at)
    def original_changed_at_sql(model)
      table = model.arel_table
      newest = [ newest_stamp(table[:translation_original_changed_at]) ]
      if [ Page, Post ].include?(model)
        blocks = ContentBlock.arel_table.alias("blocks")
        newest << newest_stamp(blocks[:translation_original_changed_at], of: blocks,
          where: blocks[:owner_type].eq(model.polymorphic_name).and(blocks[:owner_id].eq(table[:id])))
      end
      SqlNodes.coalesce(SqlNodes.function("GREATEST", *newest), table[:updated_at])
    end

    # `relation` (one model's, already read-scoped) as the translations matrix
    # lists it: only the records that are missing or outdated in any of
    # `locales`, those with an outdated language first (they are already
    # visible on the site), then the most recently changed original
    # (`original_changed_at_sql`), then the newest id. Each row carries the two
    # sort keys as `has_outdated` and `original_changed_at`, so a caller that
    # merges several models' lists can sort the merged rows the same way.
    # Replaces the relation's own order; the caller limits.
    def work_list(relation, locales:)
      model = relation.klass
      outdated = exists_in_any_locale_sql(model, states: %w[outdated], locales:)
      changed = original_changed_at_sql(model)
      relation.where(exists_in_any_locale_sql(model, states: %w[missing outdated], locales:))
        .reorder(outdated.desc, changed.desc, model.arel_table[:id].desc)
        .select(model.arel_table[Arel.star], outdated.as("has_outdated"), changed.as("original_changed_at"))
    end

    # The newest of the stamps in one `translation_original_changed_at` column
    # (a jsonb of { field => ISO time }), as a scalar subquery:
    #
    #   (SELECT MAX(CASE WHEN stamp.value ~ '<ISO_TIMESTAMP>' THEN CAST(stamp.value AS timestamptz) END)
    #    FROM [content_blocks blocks INNER JOIN] jsonb_each_text(<the column, when it is an object>) AS stamp [ON TRUE]
    #    [WHERE <the blocks of this record>])
    #
    # `of:`/`where:` are the block rows whose column is read (the function is
    # evaluated per block row, as in `FROM blocks, jsonb_each_text(...)`);
    # without them it is the outer record's own column. A column that is not a
    # JSON object reads as `{}`, and a value that is not a real ISO timestamp
    # is never cast (see `ISO_TIMESTAMP`).
    def newest_stamp(column, of: nil, where: nil)
      stamp = Arel::Table.new("stamp")
      object = Arel::Nodes::Case.new.when(SqlNodes.function("jsonb_typeof", column).eq("object")).then(column).else(SqlNodes.cast("{}", "jsonb"))
      stamps = SqlNodes.function("jsonb_each_text", object).as("stamp")
      time = Arel::Nodes::Case.new.when(stamp[:value].matches_regexp(ISO_TIMESTAMP)).then(SqlNodes.cast(stamp[:value], "timestamptz"))
      query = of ? Arel::SelectManager.new(of).join(stamps).on(Arel::Nodes::True.new).where(where) : Arel::SelectManager.new(stamps)
      Arel::Nodes::Grouping.new(query.project(time.maximum).ast)
    end

    # The join of `model`'s table to its `translation_states` rows in one
    # language (a String) or several (an Array), INNER or LEFT OUTER:
    #
    #   JOIN translation_states ON record_type = '<Model>' AND record_id = <table>.id AND locale = '<locale>'
    def state_join(model, locales, type)
      states = State.arel_table
      in_locale = locales.is_a?(Array) ? states[:locale].in(locales) : states[:locale].eq(locales)
      on = states[:record_type].eq(model.polymorphic_name).and(states[:record_id].eq(model.arel_table[:id])).and(in_locale)
      model.arel_table.join(states, type).on(on).join_sources
    end

    # Upserts one row per owner and target locale from `Status.counts`.
    def write(owners)
      locales = Translations.target_locales
      return if owners.empty? || locales.empty?

      rows = Status.counts(owners, locales:).flat_map do |owner, by_locale|
        by_locale.map do |locale, counts|
          { record_type: owner.class.polymorphic_name, record_id: owner.id, locale: locale, state: counts[:state].to_s,
            missing_count: counts[:missing], outdated_count: counts[:outdated] }
        end
      end
      State.upsert_all(rows, unique_by: %i[record_type record_id locale])
    end

    # One query for any mix of record classes.
    def rows_for(records, locales)
      records = Array(records).select(&:persisted?)
      return {} if records.empty?

      condition = records.group_by { |record| record.class.polymorphic_name }
        .map { |type, group| State.where(record_type: type, record_id: group.map(&:id)) }
        .reduce(:or)
      condition.where(locale: locales.map(&:to_s)).group_by { |row| [ row.record_type, row.record_id ] }
        .transform_values { |group| group.index_by(&:locale) }
    end

    def key(record) = [ record.class.polymorphic_name, record.id ]

    private_class_method :holds_translation, :newest_stamp, :state_join, :write, :rows_for, :key
  end
end
