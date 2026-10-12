# What a public URL shows (spec §6.3): one indexed lookup in public_paths,
# then the visibility rule for the scope. `:published` needs the record and
# every ancestor page published -- a live page under a draft section is not
# public; `:preview` (signed-in editors) shows everything. Never raises for a
# missing record: a miss is a Result like any other.
module PublicSite
  class Resolver
    # `listing_page` is set for one answer only: a post found in the PREVIEW
    # under a page whose rows list it while the post has no address (see
    # `listing_fallback`). It is the page to draw the post on.
    Result = Data.define(:status, :record, :location, :http_status, :listing_page) do
      def self.found(record, listing_page: nil) = new(status: :found, record:, location: nil, http_status: 200, listing_page:)
      # `record` is what the redirect points at -- the preview checks the
      # actor may read it before disclosing where it lives now.
      def self.redirect(location, http_status = 301, record: nil) = new(status: :redirect, record:, location:, http_status:, listing_page: nil)
      def self.not_found = new(status: :not_found, record: nil, location: nil, http_status: 404, listing_page: nil)
    end

    # The record and every ancestor page must be published -- for a post,
    # that means its *canonical* listing page and that page's own ancestors.
    # `canonical_page` prefers a published listing (spec §5.3), so this only
    # turns a post away when no published page lists it at all -- then its
    # URL runs through a draft page, reachable in preview only. One closure-table
    # query per record: `self_and_ancestors` is a scope, not a loaded array,
    # so this stays a single indexed lookup rather than N ancestor checks.
    #
    # A trashed record is never visible (trash spec §5.2). It has no
    # `public_paths` row to be found by in the first place -- this is the
    # belt to that pair of braces, and what the sitemap relies on too.
    def self.visible?(record)
      return false if record.trashed?

      pages = case record
      when Page then record.self_and_ancestors # public: rows (whether a record is visible is its tree and publish state, which no copy holds)
      when Post then (page = PublicSite::Paths.canonical_page(record)) ? page.self_and_ancestors : nil # public: rows (whether a record is visible is its tree and publish state, which no copy holds)
      end
      return false if pages.nil?
      return false if record.is_a?(Post) && !record.live?

      pages.where.not(id: Page.published.select(:id)).none? # public: rows (whether a record is visible is its tree and publish state, which no copy holds)
    end

    def initialize(scope:, urls: PublicSite::Urls.new(preview: scope == :preview))
      @scope = scope
      @urls = urls
    end

    def call(locale:, path:)
      row = PublicPath.find_by(locale: locale.to_s, path: path)
      return from_row(row, locale) if row

      listing_fallback(locale, path) || Result.not_found
    end

    private

    def from_row(row, locale)
      return Result.not_found unless visible?(row.record) # public: rows (visibility is the tree and publish state, which no copy holds)
      return Result.found(row.record) if row.current # public: rows (the resolver hands the record on; the controller reads its copy)

      target = @urls.path_for(row.record, locale) # public: rows (an address is the rows')
      target ? Result.redirect(target, record: row.record) : Result.not_found # public: rows (the resolver hands the record on; the controller reads its copy)
    end

    # "A listing page's path + a post slug" where the post lives canonically
    # somewhere else: the URL shape every listing page served before posts had
    # one canonical address (spec §5.3), kept alive as a redirect.
    def listing_fallback(locale, path)
      parent_path, _, slug = path.rpartition("/")
      page_row = PublicPath.current.find_by(record_type: "Page", locale: locale.to_s, path: parent_path.presence || "/")
      return nil if page_row.nil? || slug.blank?

      post = Post.kept.i18n.where(slug: slug, locale: locale.to_s).find { |candidate| listed_on?(page_row.record, candidate) } # public: rows (a slug is the row's; listed_on? judges by the copies)
      return nil if post.nil? || !visible?(post)

      target = @urls.path_for(post, locale)
      return Result.redirect(target, record: post) if target

      # No address at all, in the preview: the page's ROWS list the post and
      # no published copy does yet (a list block added to a live page and not
      # published). The preview shows the rows, so it shows the post here,
      # on the page that lists it; a visitor gets the 404 below.
      Result.found(post, listing_page: page_row.record) if @scope == :preview # public: rows (the preview shows the working version)
    end

    # Whether `page` lists `post`: for a visitor by the page's copy and the
    # post's (a scope on a rebuilt page's blocks would query the rows), for
    # the preview by the rows.
    def listed_on?(page, post)
      return page.content_blocks.listing.any? { |block| block.lists?(post) } if @scope == :preview # public: rows (the preview shows the working version)

      @listing_blocks ||= {}
      blocks = @listing_blocks[page.id] ||= Publishing.published(page).content_blocks.to_a
      view = Publishing.published(post)
      blocks.any? { |block| Publishing::Listing.lists?(block, view) }
    end

    # `:preview` (signed-in editors) never gates on publication state --
    # `self.class.visible?` above is the `:published` rule alone, so it is
    # only consulted when this scope actually cares about it.
    def visible?(record)
      @scope == :preview || self.class.visible?(record)
    end
  end
end
