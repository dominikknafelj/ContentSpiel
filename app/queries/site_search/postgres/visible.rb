module SiteSearch
  class Postgres
    # What a visitor at `now` sees of the entries (search spec §6.3), as Arel
    # conditions on `entries`, the `search_entries` table of the statement
    # they are put in: the copy in force (`in_force`), of a record with a
    # current address in the entry's language (`addressed`), kept and
    # published (`kept_and_published`), under no page that is not published
    # (`visible`); `all` is the four. Every pass of the built-in (the exact,
    # the close, the contains) and the close pass's candidates read them, so
    # a word or an entry only a scheduled, pending or hidden copy holds is
    # found by none.
    #
    # Decided from the site's own tables at `now`, never by a job at a
    # copy's time: a scheduled copy is found at its `live_at` and a scheduled
    # record at its `published_at`, with nothing written then.
    class Visible
      def initialize(now:, entries: Entry.arel_table)
        @now = now
        @entries = entries
      end

      def all = in_force.and(addressed).and(kept_and_published).and(visible)

      # The entry is of the copy in force: its own time has come, and no
      # entry of the same record and language is of a later copy whose time
      # has come too. Copies' ids and `live_at` rise together; the pair is
      # compared, so two copies of one moment still name one.
      def in_force
        later = Entry.arel_table.alias("later")
        newer = Arel::SelectManager.new(later).project(1).where(
          later[:record_type].eq(@entries[:record_type])
            .and(later[:record_id].eq(@entries[:record_id]))
            .and(later[:locale].eq(@entries[:locale]))
            .and(later[:live_at].lteq(quoted_now))
            .and(SqlNodes.row(later[:live_at], later[:published_version_id]).gt(SqlNodes.row(@entries[:live_at], @entries[:published_version_id])))
        )
        @entries[:live_at].lteq(quoted_now).and(newer.exists.not)
      end

      # The record has a current address in the entry's language.
      def addressed
        SqlNodes.exists(PublicPath.where(current: true).where(path_of_entry).select(:id))
      end

      # The record is not in the trash and its publication time has come.
      def kept_and_published
        [ Page, Post ].map do |model|
          kept = model.where(trashed_at: nil, published_at: ..@now).where(model.arel_table[:id].eq(@entries[:record_id])).select(:id)
          @entries[:record_type].eq(model.polymorphic_name).and(SqlNodes.exists(kept))
        end.reduce(:or)
      end

      # No page above the record is unpublished (the resolver's rule,
      # `PublicSite::Resolver.visible_among`): a page's own chain, or the
      # chain of the page that gives a post its address in this language.
      def visible
        paths = PublicPath.arel_table
        host = PublicPath.where(current: true).where(path_of_entry).where.not(listed_on_id: nil).where(hidden_above(paths[:listed_on_id]).not).select(:id)
        page = @entries[:record_type].eq(Page.polymorphic_name).and(hidden_above(@entries[:record_id]).not)
        post = @entries[:record_type].eq(Post.polymorphic_name).and(SqlNodes.exists(host))
        page.or(post)
      end

      private

      # A current address of the entry's record in the entry's language.
      def path_of_entry
        paths = PublicPath.arel_table
        paths[:record_type].eq(@entries[:record_type]).and(paths[:record_id].eq(@entries[:record_id])).and(paths[:locale].eq(@entries[:locale]))
      end

      # `EXISTS` a page above `page_id`, or the page itself, that is not
      # published at `now`.
      def hidden_above(page_id)
        hierarchy = PageHierarchy.arel_table
        SqlNodes.exists(PageHierarchy.where(hierarchy[:descendant_id].eq(page_id))
          .where.not(ancestor_id: Page.where(published_at: ..@now).select(:id)).select(:ancestor_id))
      end

      def quoted_now = SqlNodes.quoted(@now)
    end
  end
end
