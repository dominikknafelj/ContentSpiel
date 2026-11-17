module SiteSearch
  # The page that holds the site's first Search block, as published: what a
  # theme's own header search box points at (`ThemeHelper#search_page`). Read
  # from the pages' copies in force and never from their rows, so a block an
  # editor placed and did not publish, or a page that is a draft, is not it.
  #
  # FIRST is reading order, and a page counts only when it is visible
  # (kept, published, no page above it unpublished) and has a current
  # address in `locale`, the language of the page being drawn
  # (`SiteSearch::FirstHolder`, which `TagPage` shares).
  #
  # NO QUERY THE PUBLIC ETAG CANNOT SEE: everything read is what the content
  # version covers. A copy's `holds_search` is written only when it is taken
  # (the service that takes a copy bumps), and the visibility, the trash and
  # the addresses it also reads are rows whose every writer bumps too. So a
  # page that gains or loses a Search block moves the version, and so does
  # every page's ETag that draws a form pointing here.
  class SearchPage
    # The copies holding a block of a `:search` type: the flag written when a
    # copy is taken (`Publishing::Snapshot.holds_search?`), never a test of
    # the copy's `blocks` (`FirstHolder.copies_holding` says why).
    def self.holding = Publishing::Version.arel_table[:holds_search].eq(true)

    def initialize(now: Time.current, locale: I18n.locale)
      @now = now
      @locale = locale.to_s
    end

    # The page as published (a read-only view rebuilt from its copy, without
    # its blocks), or nil when the site has no Search block.
    def page
      ids = holders
      return if ids.empty?

      first = FirstHolder.first(ids, now: @now, locale: @locale) or return
      Publishing.published_all([ first ], now: @now).first
    end

    private

    # The ids of the pages whose copy in force holds a block of a `:search` type.
    def holders
      @holders ||= find_holders
    end

    def find_holders = FirstHolder.copies_holding(self.class.holding, now: @now).pluck(:record_id)
  end
end
