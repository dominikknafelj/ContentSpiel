module SiteSearch
  class Postgres
    # The built-in backend's answer to a `SiteSearch::Query` (search spec
    # §6.3): the entries of the query's language that match its words and
    # that a visitor sees at `query.now`, best first, a page of them with
    # their snippets, and how many there are.
    #
    # What a visitor sees is decided here, from the site's own tables at the
    # query's `now`, and never by a job at a copy's time: an entry is of the
    # copy in force (`in_force`), of a record with a current address in the
    # language (`addressed`), kept and published (`kept_and_published`), and
    # under no page that is not published (`visible`). So a scheduled copy is
    # found at its `live_at` and a scheduled record at its `published_at`,
    # with nothing written then.
    #
    # The visitor's words reach the database only as the bind `q`
    # (`SqlNodes.bound`), never in the statement's text, so no log line holds
    # them. Both statements run in a transaction of their own under a
    # statement timeout of the time left before the deadline, and that
    # transaction is rolled back, so the timeout ends with it whatever
    # transaction the caller is in (a `SET LOCAL` released into a savepoint's
    # parent would outlive the search).
    class Query
      # `ts_rank_cd`'s weights for D, C, B and A, and normalisation 1, which
      # divides by the log of the length, so a long page does not win by size.
      WEIGHTS = "{0.1, 0.2, 0.4, 1.0}".freeze
      NORMALISATION = 1
      HEADLINE = "StartSel=#{START_MARK}, StopSel=#{STOP_MARK}, MaxFragments=2, MaxWords=30, MinWords=12".freeze

      # The statement timeout for `seconds_left`, in whole milliseconds and at
      # least one, since Postgres reads 0 as no timeout at all; nil when no
      # time is left, and the database is not asked.
      def self.timeout_in_ms(seconds_left)
        return nil unless seconds_left.positive?

        [ (seconds_left * 1000).floor, 1 ].max
      end

      def initialize(query, deadline:)
        @query = query
        @deadline = deadline
      end

      def results
        timeout = self.class.timeout_in_ms(@deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC))
        raise ActiveRecord::QueryCanceled, "the search's deadline passed before the database was asked" unless timeout

        answer = nil
        Entry.transaction(requires_new: true) do
          # sql: Arel has no node for SET; the value is an Integer
          Entry.connection.execute("SET LOCAL statement_timeout = #{timeout}") # version: none (a setting of the search's own transaction, which writes nothing)
          answer = Results.new(hits: hits, total: total)
          raise ActiveRecord::Rollback
        end
        answer
      end

      # `websearch_to_tsquery(config, $q)`: the visitor's words parsed with
      # their language's configuration, the one the entries were built with.
      # Syntax alone or stop words alone parse to an empty query, which
      # matches nothing.
      def tsquery = SqlNodes.function("websearch_to_tsquery", regconfig, SqlNodes.bound(@query.text, name: "q"))

      # The entries a visitor at `now` finds by these words.
      def matches
        Entry.where(locale: @query.language)
          .where(Arel::Nodes::InfixOperation.new("@@", entries[:document], tsquery))
          .where(in_force).where(addressed).where(kept_and_published).where(visible)
      end

      # The entry is of the copy in force: its own time has come, and no
      # entry of the same record and language is of a later copy whose time
      # has come too. Copies' ids and `live_at` rise together; the pair is
      # compared, so two copies of one moment still name one.
      def in_force
        later = entries.alias("later")
        newer = Arel::SelectManager.new(later).project(1).where(
          later[:record_type].eq(entries[:record_type])
            .and(later[:record_id].eq(entries[:record_id]))
            .and(later[:locale].eq(entries[:locale]))
            .and(later[:live_at].lteq(now))
            .and(SqlNodes.row(later[:live_at], later[:published_version_id]).gt(SqlNodes.row(entries[:live_at], entries[:published_version_id])))
        )
        entries[:live_at].lteq(now).and(newer.exists.not)
      end

      # The record has a current address in the entry's language.
      def addressed
        SqlNodes.exists(PublicPath.where(current: true).where(path_of_entry).select(:id))
      end

      # The record is not in the trash and its publication time has come.
      def kept_and_published
        [ Page, Post ].map do |model|
          kept = model.where(trashed_at: nil, published_at: ..@query.now).where(model.arel_table[:id].eq(entries[:record_id])).select(:id)
          entries[:record_type].eq(model.polymorphic_name).and(SqlNodes.exists(kept))
        end.reduce(:or)
      end

      # No page above the record is unpublished (the resolver's rule,
      # `PublicSite::Resolver.visible_among`): a page's own chain, or the
      # chain of the page that gives a post its address in this language.
      def visible
        paths = PublicPath.arel_table
        host = PublicPath.where(current: true).where(path_of_entry).where.not(listed_on_id: nil).where(hidden_above(paths[:listed_on_id]).not).select(:id)
        page = entries[:record_type].eq(Page.polymorphic_name).and(hidden_above(entries[:record_id]).not)
        post = entries[:record_type].eq(Post.polymorphic_name).and(SqlNodes.exists(host))
        page.or(post)
      end

      # `ts_rank_cd(weights, document, tsquery, 1)`: a title's match outranks
      # a summary's, a body's and a code's.
      def rank = SqlNodes.function("ts_rank_cd", SqlNodes.cast(WEIGHTS, "real[]"), entries[:document], tsquery, NORMALISATION)

      # `ts_headline` over a hit's text, the matched words between the two
      # marks.
      def headline(text) = SqlNodes.function("ts_headline", regconfig, text, tsquery, HEADLINE)

      def total = matches.count

      private

      # The page's hits: ranked and cut in the inner query, and only those
      # rows given a headline, which is the expensive part.
      def hits
        ranked = matches
          .select(entries[:record_type], entries[:record_id], entries[:published_version_id], entries[:text], rank.as("rank"))
          .order(rank.desc, entries[:record_type].asc, entries[:record_id].asc)
          .limit(@query.per_page).offset(@query.offset)
        page = entries.alias("hits")
        Entry.from(ranked, :hits)
          .order(page[:rank].desc, page[:record_type].asc, page[:record_id].asc)
          .pluck(page[:record_type], page[:record_id], page[:published_version_id], page[:rank], headline(page[:text]))
          .map do |record_type, record_id, copy_id, rank, headline|
            Hit.new(record_type: record_type, record_id: record_id, copy_id: copy_id, language: @query.language,
              snippet: Postgres.snippet_of(headline), rank: rank)
          end
      end

      # A current address of the entry's record in the entry's language.
      def path_of_entry
        paths = PublicPath.arel_table
        paths[:record_type].eq(entries[:record_type]).and(paths[:record_id].eq(entries[:record_id])).and(paths[:locale].eq(entries[:locale]))
      end

      # `EXISTS` a page above `page_id`, or the page itself, that is not
      # published at `now`.
      def hidden_above(page_id)
        hierarchy = PageHierarchy.arel_table
        SqlNodes.exists(PageHierarchy.where(hierarchy[:descendant_id].eq(page_id))
          .where.not(ancestor_id: Page.where(published_at: ..@query.now).select(:id)).select(:ancestor_id))
      end

      def regconfig = SqlNodes.cast(Postgres.config_for(@query.language), "regconfig")

      def now = SqlNodes.quoted(@query.now)

      def entries = Entry.arel_table
    end
  end
end
