# Derives and stores every public URL (spec §5.4). Called from model
# callbacks (HasPublicPaths) rather than from services on purpose: CS
# Studio, seeds and fixtures-built data all save through ActiveRecord, and
# every one of those writes has to leave the URL table correct.
module PublicSite
  module Paths
    # One address that differs from what is stored: the record's current row
    # in `locale` (`row_id` and its path `from`, both nil when it has none)
    # and the path it should have (`to`, nil for none).
    Change = Struct.new(:record, :locale, :row_id, :from, :to)

    module_function

    def current_path(record, locale)
      PublicPath.current.find_by(record: record, locale: locale.to_s)&.path
    end

    # { locale => path or nil } for every enabled locale. nil means "no URL"
    # (a post nothing lists, a non-root page with a blank slug, anything in
    # the trash).
    #
    # Reads the *stored* current path of what the record hangs off (a page's
    # parent, a post's canonical listing page) rather than recursing back up
    # the tree in Ruby, which is also why this is safe to call on an unsaved
    # record: `HasPublicPaths#public_paths_are_available` calls it from a
    # `validate`, before the record (or its would-be row here) exists at all.
    # A fixed number of queries either way: one for a page (its parent's
    # rows, every language at once), `canonical_pages`' own plus one for a
    # post.
    def compute(record)
      case record
      when Page then page_paths(record, current_paths("Page", [ record.parent_id ].compact).fetch(record.parent_id, {}))
      when Post then post_paths([ record ]).fetch(record)
      else Locales.enabled.index_with { nil }
      end
    end

    def sync(record)
      write_all({ record => compute(record) })
    end

    # A page and everything below it, in a number of statements that doesn't
    # depend on how many pages that is: the pages below in one query, their
    # stored rows (and the parent's, which the top page hangs off) in another,
    # every path worked out in memory top-down -- each page from the path
    # just computed for its parent, never from that parent's stored row,
    # which is about to be replaced -- and then only the rows that differ
    # written, a set at a time (`write_all`).
    #
    # The pages below are found by `parent_id`, not through `children` or the
    # closure table: an association loaded earlier in the request would still
    # hand back child objects holding their pre-save slugs, and a page's path
    # is its ancestors' slugs plus its own; and `parent_id` is the one thing
    # every page has, closure rows or not. `UNION`, not `UNION ALL`, so a
    # `parent_id` loop written around the model could never spin the query.
    #
    # Trashed pages are in the set on purpose: `compute_path` gives them nil,
    # their descendants then find no parent path, and so one pass over a
    # branch `Trash::Move` has just flagged (its members with `update_all`,
    # the root saved last) deletes every member's rows.
    #
    # The top page is the object the caller holds -- inside its own
    # `after_save` that is the record as just written -- and everything below
    # is read from the database.
    def sync_subtree(page)
      below = Page.where(<<~SQL.squish, page.id).order(:id).group_by(&:parent_id)
        pages.id IN (
          WITH RECURSIVE below AS (
            SELECT id FROM pages WHERE parent_id = ?
            UNION
            SELECT pages.id FROM pages JOIN below ON pages.parent_id = below.id
          )
          SELECT id FROM below
        )
      SQL
      pages = [ page ]
      pages.each { |parent| pages.concat(below.fetch(parent.id, [])) }

      stored = current_rows("Page", [ page.parent_id, *pages.map(&:id) ].compact)
      above = stored.filter_map { |(_, id, locale), (_, path)| [ locale, path ] if id == page.parent_id }.to_h
      paths = { page.parent_id => above }
      desired = pages.index_with { |member| paths[member.id] = page_paths(member, paths.fetch(member.parent_id, {})) }

      write_all(desired, stored: stored)
    end

    # Every post, or every post of one content type, re-derives its canonical
    # page and current path from scratch (spec §5.4): a `post_list` block's
    # own save/destroy, and a page save that changes one of its URL inputs
    # (a move, reorder, publish or trash included -- `Page#resync_listed_posts`,
    # for the types its subtree's blocks list), both call this rather than
    # `sync`ing one post at a time, because either can hand a post its first
    # canonical page, take it away, or move it to a *different* page than the
    # one that just changed -- something a single record's own callback has
    # no way to know about.
    #
    # `content_type` is `nil` for "every post" (a content-type-less
    # post_list block matches every type itself) -- `Post.all`, not a
    # `where(content_type: nil)` that would compile to a no-op the way
    # `ContentBlock#listed_posts` warns against.
    #
    # A batch at a time, each in a fixed number of statements: the posts and
    # their tags (`includes(:tags)`, which `ContentBlock#lists?`'s tag check
    # reads for every listing block), `canonical_pages` for the whole batch
    # at once, those pages' current paths, the posts' stored rows, and then
    # the writes for whatever differs.
    def sync_posts(content_type)
      scope = content_type ? Post.where(content_type: content_type) : Post.all
      scope.includes(:tags).find_in_batches { |posts| write_all(post_paths(posts)) }
    end

    def rebuild!
      PublicPath.transaction do
        PublicPath.delete_all
        root = Page.find_by(parent_id: nil)
        sync_subtree(root) if root
        sync_posts(nil)
      end
    end

    # One record's path in one language, given the path of what it hangs off
    # in that language (`above`: a page's parent, a post's canonical listing
    # page; nil when that has no URL).
    #
    # A post or page of an unregistered stored type gets no path at all: it
    # renders nothing on the public site (global constraints -- unknown
    # stored types never 500 it), so it must not be reachable at a URL
    # either. Only `Post` has a type to check here -- a `Page`'s `page_type`
    # is a closed enum (layout, not open content), so it has no equivalent
    # "unregistered" state.
    #
    # A trashed page or post has no URL either (trash spec §5.2). Returning
    # nil here, rather than deleting rows from the trash services, is what
    # keeps every other writer -- `rebuild!`, `sync_posts`, an ancestor's
    # `sync_subtree` -- from ever giving it one back; a record whose path
    # comes out nil loses its current row *and* its redirects for that
    # locale (`write_all`). A trashed page's descendants follow without a
    # check of their own: `page_path` is handed no path for their parent and
    # returns nil. Restoring is the same save in reverse: `trashed_at`
    # cleared, the model's own `after_save` sync writes the rows afresh (old
    # redirects are not resurrected -- they were deleted, not demoted).
    def compute_path(record, locale, above)
      return nil if record.respond_to?(:trashed?) && record.trashed?

      case record
      when Page then page_path(record, locale, above)
      when Post
        if record.definition.nil?
          Rails.logger.warn("[public_paths] Post##{record.id} gets no #{locale} URL: " \
            "#{record.content_type.inspect} isn't a registered content type")
          nil
        else
          post_path(record, locale, above)
        end
      end
    end

    # A page's `{ locale => path }`, given its parent's `{ locale => path }`.
    def page_paths(page, parent_paths)
      Locales.enabled.index_with { |locale| compute_path(page, locale, parent_paths[locale.to_s]) }
    end

    # `{ post => { locale => path } }` for several posts in one pass: their
    # canonical pages together (`canonical_pages`), then those pages' current
    # paths in one query.
    def post_paths(posts)
      pages = canonical_pages(posts)
      listing_paths = current_paths("Page", pages.values.compact.map(&:id).uniq)

      posts.index_with do |post|
        above = listing_paths.fetch(pages[post]&.id, {})
        Locales.enabled.index_with { |locale| compute_path(post, locale, above[locale.to_s]) }
      end
    end

    # `{ record id => { locale => current path } }` for records of one type,
    # in one query.
    def current_paths(record_type, ids)
      return {} if ids.empty?

      PublicPath.current.where(record_type: record_type, record_id: ids).pluck(:record_id, :locale, :path)
        .each_with_object({}) { |(id, locale, path), paths| (paths[id] ||= {})[locale] = path }
    end

    # `{ [record type, record id, locale] => [row id, path] }`: the current
    # rows of records of one type, as `write_all` compares against.
    def current_rows(record_type, ids)
      return {} if ids.empty?

      PublicPath.current.where(record_type: record_type, record_id: ids).pluck(:id, :record_id, :locale, :path)
        .to_h { |row_id, id, locale, path| [ [ record_type, id, locale ], [ row_id, path ] ] }
    end

    # The page a post's URL runs through (spec §5.3): the best of every page
    # with a post_list block that lists `post`, ranked by, in order,
    #
    # 1. publication -- a candidate whose whole page chain (the page and every
    #    ancestor) is live comes before one that isn't. Without this, a draft
    #    page earlier in the tree takes every matching post's URL, the
    #    resolver then 404s them publicly (`Resolver.visible?` checks this
    #    same page's chain), and the published listing links to those 404s --
    #    leaking the draft page's slug in its hrefs. An unpublished candidate
    #    still wins when it is the *only* kind there is, so a post listed only
    #    by a draft page keeps a URL there and `/preview` can show it.
    #
    #    "Live" is `Publishable#live?`, so a *scheduled* page counts as
    #    unpublished until its time comes -- and nothing writes a row at that
    #    moment, so posts don't move onto a scheduled listing page when it
    #    goes live, only at the next sync that reaches them (a save of that
    #    page or an ancestor that changes one of its URL inputs, a write to a
    #    listing block, a save of the post that changes one of its own, or
    #    `rebuild!`). Until then they stay
    #    at the published listing they already had, which keeps serving them;
    #    the ETag already changes at go-live (`PublicSite.content_version`), so
    #    the page itself isn't served stale.
    #
    # 2. specificity -- a block naming the post's content type beats an
    #    unfiltered one, then a block whose tag the post carries beats one
    #    with no tag filter. This is what keeps a homepage "latest posts"
    #    teaser (unfiltered, and on the root, which always comes first in tree
    #    order) from taking every post's URL away from /blog. (A block that
    #    names a *different* type or a tag the post lacks isn't a candidate at
    #    all -- `lists?` already said no.)
    #
    # 3. tree order -- depth-first by sibling position, as the tiebreak. That
    #    is the page whose own position, then its parent's, and so on up to
    #    the root, sorts lowest: `self_and_ancestors` (closure_tree, root
    #    last) reversed puts the root's position first and this page's own
    #    last, so comparing those arrays lexicographically ranks an earlier
    #    branch ahead of a later one at whichever ancestor they diverge, and
    #    only falls through to a deeper `position` when every shallower one
    #    ties -- which happens only between a page and its own descendant,
    #    never between two different pages, since sibling `position` values
    #    are unique (closure_tree's own invariant).
    #
    # One `self_and_ancestors` load per candidate page serves both (1) and
    # (3). Ranked per *block*, not per page: a page carrying both a teaser and
    # a typed listing competes with its most specific one.
    #
    # Every post_list block is checked, not just the ones on already-synced
    # pages: this is also what a block's own save/destroy calls (via
    # `sync_posts`), where nothing about the page tree changed at all.
    def canonical_page(post) = canonical_pages([ post ]).fetch(post)

    # `canonical_page` for several posts in ONE pass: `{ post => page or nil }`.
    # The listing blocks, their owners and every candidate's ancestry are loaded
    # once (a constant number of queries however many posts, blocks or pages
    # there are), then each post is ranked among the blocks that list it. The
    # New post dialog asks for every creatable type's listing page at once.
    def canonical_pages(posts)
      # `ContentBlock.listing` is every block whose type has the
      # `lists_posts` capability -- only a `Page` owner is a candidate at
      # all (open-types spec §4.1 lets other records own blocks too, but
      # none render a listing of their own posts today).
      # A block on a trashed page isn't a candidate either (trash spec §5.2):
      # its posts move to the next-best listing, or lose their URL, and
      # come back here when the page is restored.
      candidates = ContentBlock.listing.includes(:owner).select { |block| block.owner.is_a?(Page) && !block.owner.trashed? }
      chains = ancestry_chains(candidates.map(&:owner).uniq)

      posts.index_with do |post|
        best = candidates.select { |block| block.lists?(post) }.min_by do |block|
          chain = chains.fetch(block.owner.id, [])
          settings = block.settings_object
          [
            chain.all?(&:live?) ? 0 : 1,
            settings.content_type.present? ? 0 : 1,
            settings.tag.to_s.strip.present? ? 0 : 1,
            chain.map { |page| page.position.to_i }
          ]
        end
        best&.owner
      end
    end

    # `{ page id => [root, ..., page] }` for every page given -- what
    # `page.self_and_ancestors.to_a.reverse` is, for all of them from two
    # queries (the closure rows, then the pages on them).
    def ancestry_chains(pages)
      return {} if pages.empty?

      rows = Page.hierarchy_class.where(descendant_id: pages.map(&:id)).pluck(:descendant_id, :ancestor_id, :generations)
      by_id = Page.where(id: rows.map { |_, ancestor_id, _| ancestor_id }.uniq).index_by(&:id)
      rows.group_by(&:first).transform_values do |list|
        list.sort_by { |_, _, generations| -generations }.filter_map { |_, ancestor_id, _| by_id[ancestor_id] }
      end
    end

    # A post's path is its canonical listing page's current path, then `/`,
    # then its own slug -- nil (no URL) when it has no canonical page, or that
    # page itself currently has no path (mid-move). A canonical page that is
    # unpublished (only chosen when no published candidate exists, see
    # `canonical_page`) still gives the post a path: the resolver's
    # publication check is what keeps it off the public site.
    def post_path(post, locale, listing_path)
      join(listing_path, segment(post, locale))
    end

    # The root is exempt from needing a slug of its own: it contributes no
    # segment and its path is "/" by design (see `Page#validates :slug`).
    # Every other page's path is its parent's path plus its own segment, so a
    # blank segment or a parent without a path (in the trash, or itself
    # without a slug) both come back nil rather than silently landing on the
    # parent's own address -- the two-pages-one-URL collision `cached_paths`
    # used to allow is something `HasPublicPaths`'s validation and the
    # `(locale, path)` unique index both refuse outright, so nil here is "no
    # URL yet", never "borrow one".
    def page_path(page, locale, parent_path)
      return "/" if page.parent_id.nil?

      join(parent_path, segment(page, locale))
    end

    # The record's slug in `locale`, read literally (a slug has no fallback).
    def segment(record, locale)
      record.public_send(Mobility.normalize_locale_accessor(:slug, locale))
    end

    def join(above, segment)
      return nil if above.nil? || segment.blank?

      above == "/" ? "/#{segment}" : "#{above}/#{segment}"
    end

    # Moves one record's current row to `path` in `locale`; see `write_all`,
    # which this is for a single address.
    def write(record, locale, path)
      write_all({ record => { locale => path } })
    end

    # Brings the current rows of `desired` (`{ record => { locale => path or
    # nil } }`, the records all of one class) to those paths, writing only
    # what differs from `stored` (their rows as `current_rows` reads them,
    # read here when the caller hasn't already), in a number of statements
    # that doesn't depend on how many records or rows there are.
    #
    # For each record and locale whose path changed:
    # - the old current row stays behind as a redirect;
    # - a redirect row already holding the new path (any record's) is
    #   dropped so the address can be reused;
    # - no path at all removes the record's rows for that locale, redirects
    #   included, since there is nowhere left to redirect them to;
    # - a path that is another record's *current* address is not taken: see
    #   `held_by_others` and `yield_to_holder`. Neither is a path an earlier
    #   record of this same call has just been given (the records are taken
    #   in the order handed in: pages top-down, posts by id).
    #
    # The order of the statements is what the two unique indexes need: rows
    # that go are deleted and outgoing rows demoted before anything is
    # inserted (one current row per record and locale), and a demoted row is
    # a redirect by the time redirects on the new paths are dropped -- so a
    # record may take the address another record of the same call has just
    # left (one address per locale, redirects included).
    #
    # `update_all`, `delete_all` and `insert_all!`, never a model save: this
    # runs from inside another record's `after_save`, and re-entering
    # callbacks or validations on a row nobody edited would be both wasted
    # work and a risk of failing a save that was never actually invalid.
    # `insert_all!`, with the bang: a path that did turn out to be taken is
    # an exception, not a row silently left out.
    def write_all(desired, stored: nil)
      records = desired.keys
      return if records.empty?

      type = records.first.class.polymorphic_name
      stored ||= current_rows(type, records.filter_map(&:id))
      changes = desired.flat_map do |record, paths|
        paths.filter_map do |locale, path|
          row_id, from = stored[[ type, record.id, locale.to_s ]]
          Change.new(record, locale.to_s, row_id, from, path) unless from == path
        end
      end
      return if changes.empty?

      PublicPath.transaction do
        held = held_by_others(changes)
        given = Set.new
        moved, rest = changes.partition { |change| change.to && !held.include?([ change.locale, change.to ]) && given.add?([ change.locale, change.to ]) }
        gone, yielding = rest.partition { |change| change.to.nil? }
        yielding.each { |change| yield_to_holder(change) }

        delete_rows(gone)
        PublicPath.where(id: yielding.filter_map(&:row_id)).delete_all if yielding.any?(&:row_id)
        PublicPath.where(id: moved.filter_map(&:row_id)).update_all(current: false, updated_at: Time.current) if moved.any?(&:row_id)
        if moved.any?
          addresses(PublicPath.redirects, moved.map { |change| [ change.locale, change.to ] }).delete_all
          # Timestamps from the application clock, as a model save writes
          # them (left to `insert_all!` they would be the database's
          # transaction start time).
          now = Time.current
          PublicPath.insert_all!(moved.map do |change|
            { record_type: type, record_id: change.record.id, locale: change.locale, path: change.to, current: true, created_at: now, updated_at: now }
          end)
        end

        (gone + moved).each { |change| announce(change.record, change.locale, change.from, change.to) }
      end
    end

    # The `[locale, path]` pairs among the wanted paths that are some *other*
    # record's live address and will still be after this call -- a current
    # row that one of these changes is itself moving away, or deleting, holds
    # nothing any more.
    #
    # The record's own save never gets this far with such a path --
    # `HasPublicPaths#public_paths_are_available` turns it into a validation
    # error first (spec §5.2) -- so a hit here means the sync was triggered
    # by a *different* record's write: a post_list block saved or destroyed
    # (`ContentBlock#sync_listed_post_paths`), a page saved, moved or
    # reordered (`Page#sync_public_paths`, including a cascade into its
    # descendants), a tag added or removed (`PostTag#sync_post_paths`), or a
    # language enabled. E.g. page /blog/team plus post "team" living at /team
    # via a homepage listing: removing that homepage block moves the post
    # onto /blog/team, which the page holds.
    def held_by_others(changes)
      wanted = changes.filter_map(&:to).uniq
      return Set.new if wanted.empty?

      leaving = changes.filter_map(&:row_id).to_set
      pairs = changes.filter_map { |change| [ change.locale, change.to ] if change.to }.to_set
      PublicPath.current.where(path: wanted).pluck(:id, :locale, :path)
        .filter_map { |row_id, locale, path| [ locale, path ] if !leaving.include?(row_id) && pairs.include?([ locale, path ]) }.to_set
    end

    # The record that did not ask for this sync goes without a URL in this
    # locale rather than raising: the unique index would otherwise throw
    # `RecordNotUnique` out of somebody else's save -- a 500 on a block
    # removal the editor can't get past, or, from `PostTag`'s `after_commit`,
    # an exception after the data is already committed. Its current row (if
    # it had one) is deleted by `write_all`, not demoted: nothing else may
    # claim that old address as a redirect *to* a record with no address. Its
    # existing redirect rows are kept; they resolve to a 404 while it has no
    # current row (`Resolver#from_row` finds no target) and start 301ing
    # again once a later sync gives it one -- after the clash is removed, the
    # next sync that reaches the record does (a save of it that changes one
    # of its URL inputs, any of the triggers above, or `rebuild!`; a save
    # that changes none does not look). Logged, since nothing on screen says
    # why the record vanished from that address.
    def yield_to_holder(change)
      record = change.record
      Rails.logger.warn("[public_paths] #{record.class.polymorphic_name}##{record.id} gets no #{change.locale} URL: " \
        "#{change.to} is already another record's current path")
      announce(record, change.locale, change.from, nil) if change.row_id
    end

    # Every row -- current and redirects alike -- of the records and locales
    # whose path is gone, in one statement.
    def delete_rows(gone)
      return if gone.empty?

      gone.group_by(&:locale).map do |locale, changes|
        PublicPath.where(record_type: changes.first.record.class.polymorphic_name, record_id: changes.map { |change| change.record.id }, locale: locale)
      end.reduce(:or).delete_all
    end

    # `scope` narrowed to the given `[locale, path]` pairs, as one condition.
    def addresses(scope, pairs)
      pairs.group_by(&:first).map { |locale, list| scope.where(locale: locale, path: list.map(&:last)) }.reduce(:or)
    end

    # Deferred to after the whole transaction commits (spec §5.4): a sync runs
    # inside the record's own save, and a subscriber reacting to a path that
    # the surrounding transaction goes on to roll back would be announcing a
    # change that never actually happened.
    def announce(record, locale, from, to)
      ActiveRecord.after_all_transactions_commit do
        ActiveSupport::Notifications.instrument("public_paths.changed", record: record, locale: locale, from: from, to: to)
      end
    end
  end
end
