module SiteSearch
  # The first page in reading order among pages that hold something in their
  # copy in force: the site's search page (`SearchPage`, the first holding a
  # Search block) and a tag's listing page (`TagPage`, the first listing the
  # tag). Handed the holders' ids, it keeps those a visitor of `locale` can
  # reach at `now`: kept, published, visible (no page above unpublished:
  # `PublicSite::Resolver.visible_among`) and with a current address in the
  # language.
  #
  # FIRST is reading order: the chain of (position, id) keys from the
  # homepage down (`TreeOrder.key`), compared as arrays, so a page comes
  # before its own subpages and each branch before the next sibling's.
  #
  # One pass over every holder answers each group of them (`#first(among)`),
  # so a caller with several groups (one per tag) asks the tree once.
  class FirstHolder
    # The pages' copies in force at `now` that carry `flag` (an Arel node over
    # a copy's flags, `holds_search` or `lists_posts`, written when the copy
    # is taken) and meet `condition`, when there is one (a node over the
    # copy's `blocks`).
    #
    # NEVER A COPY OF THE HISTORY: the grouping that finds each page's copy in
    # force is narrowed INSIDE to the pages one of whose copies ever carried
    # the flag (`index_published_versions_holding_search` serves the search
    # flag), and the flag is asked again of the copies in force, before
    # `condition`. Asking `blocks @>` of the copies in force as a filter of
    # the whole table was a sequential scan that read and decompressed the
    # `blocks` of every copy ever taken, about 44 ms on every page of a site
    # republished many times, and more with every publish
    # (`test/queries/site_search/search_page_test.rb`: "the search page is
    # found from the flags and never reads a copy's blocks").
    #
    # Taking a copy deletes the pending one (`Publishing::Version`), so `max(id)` in force is the greatest `(live_at, id)`, as `Version.current_for`.
    def self.copies_holding(flag, now:, condition: nil)
      versions = Publishing::Version.unscoped
      ever = versions.where(record_type: "Page").where(flag).select(:record_id)
      newest = versions.where(record_type: "Page", record_id: ever).in_force(now).group(:record_id).select(Publishing::Version.arel_table[:id].maximum)
      current = versions.where(id: newest).where(flag)
      condition ? current.where(condition) : current
    end

    # The first of `ids` in reading order that a visitor can reach, a row,
    # or nil.
    def self.first(ids, now:, locale:) = new(ids, now: now, locale: locale).first

    def initialize(ids, now:, locale:)
      @ids = ids.uniq
      @now = now
      @locale = locale.to_s
    end

    # The first of `among` (some of the ids handed in, all by default) in
    # reading order, as a row, or nil.
    def first(among = @ids)
      among = among.to_set
      reachable.select { |row| among.include?(row.id) }.min_by { |row| place_of(row) }
    end

    private

    def reachable
      @reachable ||= begin
        rows = @ids.empty? ? [] : Page.kept.where(id: @ids, published_at: ..@now).to_a # public: rows (the trash and the publication time are the rows', a caller reads the copy)
        rows = PublicSite::Resolver.visible_among(rows, now: @now) # public: rows (whether a page is visible is its tree and publish state, which no copy holds)
        addressed = rows.empty? ? Set.new : PublicPath.where(record_type: "Page", locale: @locale, current: true).where(record_id: rows.map(&:id)).pluck(:record_id).to_set
        rows.select { |row| addressed.include?(row.id) }
      end
    end

    def place_of(row) = chains.fetch(row.id, []).map { |_, ancestor| places.fetch(ancestor) }

    def chains
      @chains ||= PageHierarchy.where(descendant_id: reachable.map(&:id)).order(generations: :desc).pluck(:descendant_id, :ancestor_id).group_by(&:first) # public: rows (the tree's order)
    end

    def places
      @places ||= Page.where(id: chains.values.flatten.uniq).pluck(:id, :position).to_h { |id, position| [ id, TreeOrder.key(position, id) ] } # public: rows (the tree's order)
    end
  end
end
