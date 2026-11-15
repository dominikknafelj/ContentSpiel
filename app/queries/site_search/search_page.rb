module SiteSearch
  # The page that holds the site's first Search block, as published: what a
  # theme's own header search box points at (`ThemeHelper#search_page`). Read
  # from the pages' copies in force and never from their rows, so a block an
  # editor placed and did not publish, or a page that is a draft, is not it.
  #
  # FIRST is reading order: the chain of (position, id) keys from the
  # homepage down (`TreeOrder.key`), compared as arrays, so a page comes
  # before its own subpages and each branch before the next sibling's.
  #
  # NO QUERY THE PUBLIC ETAG CANNOT SEE: everything read is what the content
  # version covers. A copy's `blocks` change only when a copy is taken
  # (the service that takes a copy bumps), and the visibility, the trash and
  # the addresses it also reads are rows whose every writer bumps too. So a
  # page that gains or loses a Search block moves the version, and so does
  # every page's ETag that draws a form pointing here.
  #
  # A page counts only when it is visible (kept, published, no page above it
  # unpublished: `PublicSite::Resolver.visible_among`) and has a current
  # address in `locale`, the language of the page being drawn.
  class SearchPage
    def initialize(now: Time.current, locale: I18n.locale)
      @now = now
      @locale = locale.to_s
    end

    # The page as published (a read-only view rebuilt from its copy, without
    # its blocks), or nil when the site has no Search block.
    def page
      ids = holders
      return if ids.empty?

      rows = Page.kept.where(id: ids, published_at: ..@now).to_a # public: rows (the trash and the publication time are the rows', the copy is read below)
      rows = PublicSite::Resolver.visible_among(rows) # public: rows (whether a page is visible is its tree and publish state, which no copy holds)
      rows = rows.select { |row| addressed.include?(row.id) }
      first = first_in_reading_order(rows) or return

      Publishing.published_all([ first ], now: @now).first
    end

    private

    # The ids of the pages whose copy in force holds a block of a `:search` type.
    def holders
      @holders ||= find_holders
    end

    def find_holders
      names = BlockTypes.with_capability(:search).map(&:name)
      return [] if names.empty?

      holding = names.map { |name| SqlNodes.json_contains(Publishing::Version.arel_table[:blocks], [ { "block_type" => name } ]) }.reduce(:or)
      newest = Publishing::Version.unscoped.where(record_type: "Page").in_force(@now).group(:record_id).select(Publishing::Version.arel_table[:id].maximum)
      Publishing::Version.unscoped.where(id: newest).where(holding).pluck(:record_id)
    end

    def addressed
      @addressed ||= PublicPath.where(record_type: "Page", locale: @locale, current: true).where(record_id: holders).pluck(:record_id).to_set
    end

    def first_in_reading_order(rows)
      return if rows.empty?

      chains = PageHierarchy.where(descendant_id: rows.map(&:id)).order(generations: :desc).pluck(:descendant_id, :ancestor_id).group_by(&:first) # public: rows (the tree's order)
      places = Page.where(id: chains.values.flatten.uniq).pluck(:id, :position).to_h { |id, position| [ id, TreeOrder.key(position, id) ] } # public: rows (the tree's order)
      rows.min_by { |row| chains.fetch(row.id, []).map { |_, ancestor| places.fetch(ancestor) } }
    end
  end
end
