module SiteSearch
  # A backend's hits checked again before they are drawn (spec §5.6), since
  # an outside index can be stale: a hit is kept only when its record is
  # kept and published at `now`, visible (`PublicSite::Resolver.visible_among`:
  # no page above it unpublished), has a current address in the language,
  # and the hit's copy is the record's copy in force. What is drawn of it,
  # the title, the address, the place and the date, is read from that copy
  # and `public_paths`, never from the engine (a document's `url` is for an
  # engine's own tools).
  #
  # A hit dropped here is not replaced: the page shows fewer than ten and the
  # total stays the engine's. With the built-in nothing is dropped, since its
  # query asks the same (`test/models/site_search/shown_test.rb` holds the
  # two to agree).
  #
  # THE STATEMENTS, whatever the number of hits: the records, one per kind;
  # their copies in force, one per kind (`Publishing.published_all`); the
  # visibility rule's (`visible_among`: a post's canonical page, the closure
  # query); their addresses, one per kind (`PublicSite::Urls#prefetch`); and
  # for the pages, the pages above them and those pages' copies.
  module Shown
    # One hit as a template may draw it. `kind` `:page` or `:post`; `record`
    # the published view (read-only, rebuilt from the copy in force);
    # `title` as published, in the language through its fallback; `url_path`
    # its current address with the language's prefix; `where` a page's
    # ancestors' titles from the homepage down, as published (nil for a post
    # and for the homepage); `date` a post's `published_at`, the moment the
    # site's `post_date` writes (nil for a page); `snippet` the backend's
    # `SiteSearch::Snippet`, plain text and ranges.
    Item = Data.define(:kind, :record, :title, :url_path, :where, :date, :snippet)

    MODELS = { "Page" => Page, "Post" => Post }.freeze
    KINDS = { "Page" => :page, "Post" => :post }.freeze

    module_function

    # The hits of `results` that a visitor at `now` sees in `locale`, as
    # `Item`s in the backend's order.
    def for(results, locale:, now:)
      hits = results.hits.select { |hit| MODELS.key?(hit.record_type) }
      return [] if hits.empty?

      locale = locale.to_s
      rows = rows_of(hits, now)
      visible = PublicSite::Resolver.visible_among(rows.values, now: now).to_set # public: rows (whether a record is visible is its tree and publish state, which no copy holds)
      views = views_of(rows.values.select { |row| visible.include?(row) }, now)
      urls = PublicSite::Urls.new.prefetch(views.values, locale)
      places = places_of(views.values.select { |view| view.is_a?(Page) }, locale, now)

      hits.filter_map do |hit|
        view = views[[ hit.record_type, hit.record_id ]]
        next unless view && view.published_version&.id == hit.copy_id

        path = urls.path_for(view, locale) or next
        item_of(hit, view, path, places, locale)
      end
    end

    # `{ [type, id] => row }` of the hits' records that are kept and
    # published at `now`.
    def rows_of(hits, now)
      hits.group_by(&:record_type).flat_map do |type, group|
        MODELS.fetch(type).kept.where(id: group.map(&:record_id).uniq, published_at: ..now).to_a # public: rows (the trash and the publication time are the rows', and a copy is read for each below)
      end.index_by { |row| [ row.class.polymorphic_name, row.id ] }
    end

    # `{ [type, id] => view }`, each record as published at `now`. A post's
    # body is left unread: a result draws the backend's snippet.
    def views_of(rows, now)
      pages, posts = rows.partition { |row| row.is_a?(Page) }
      (Publishing.published_all(pages, now: now) + Publishing.published_all(posts, now: now, without_body: true))
        .index_by { |view| [ view.class.polymorphic_name, view.id ] }
    end

    # `{ page id => [title, …] }`: the titles of the pages above each page,
    # the homepage first, as published. A page with none above has no entry.
    def places_of(pages, locale, now)
      return {} if pages.empty?

      above = PageHierarchy.where(descendant_id: pages.map(&:id)).where(generations: 1..)
        .order(generations: :desc).pluck(:descendant_id, :ancestor_id) # public: rows (which pages are above is the tree's; every title is read from a copy)
      return {} if above.empty?

      ancestors = Page.where(id: above.map(&:last).uniq).to_a # public: rows (a copy is read for each below)
      titles = Publishing.published_all(ancestors, now: now).to_h { |view| [ view.id, Locales.read(view, :title, locale: locale) ] }
      above.group_by(&:first).transform_values { |pairs| pairs.map { |_, id| titles[id] }.compact }
    end

    def item_of(hit, view, path, places, locale)
      page = view.is_a?(Page)
      Item.new(kind: KINDS.fetch(hit.record_type), record: view, title: Locales.read(view, :title, locale: locale), url_path: path,
        where: (places[view.id].presence if page), date: (view.published_at unless page), snippet: hit.snippet)
    end

    private_class_method :rows_of, :views_of, :places_of, :item_of
  end
end
