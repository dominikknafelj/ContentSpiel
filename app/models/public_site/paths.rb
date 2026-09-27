# Derives and stores every public URL (spec §5.4). Called from model
# callbacks (HasPublicPaths) rather than from services on purpose: Avo,
# seeds and fixtures-built data all save through ActiveRecord, and every
# one of those writes has to leave the URL table correct.
module PublicSite
  module Paths
    module_function

    def current_path(record, locale)
      PublicPath.current.find_by(record: record, locale: locale.to_s)&.path
    end

    # { locale => path or nil } for every enabled locale. nil means "no URL"
    # (a post nothing lists, a non-root page with a blank slug).
    #
    # Reads the parent's *stored* current path rather than recursing back up
    # the tree in Ruby, which is also why this is safe to call on an unsaved
    # record: `HasPublicPaths#public_paths_are_available` calls it from a
    # `validate`, before the record (or its would-be row here) exists at all.
    def compute(record)
      Locales.enabled.index_with { |locale| compute_path(record, locale) }
    end

    def sync(record)
      compute(record).each { |locale, path| write(record, locale, path) }
    end

    # A page and everything below it, top-down, reading each parent's freshly
    # written row. Queried by `parent_id` rather than through `children` --
    # the "don't touch" cascade query `Page#write_cached_paths` used to run,
    # carried over here for the same reason: an association loaded earlier in
    # the request would still hand back child objects holding their pre-save
    # slugs, and a page's path is its ancestors' slugs plus its own.
    def sync_subtree(page)
      sync(page)
      Page.where(parent_id: page.id).find_each { |child| sync_subtree(child) }
    end

    # Every post, or every post of one content type, re-derives its canonical
    # page and current path from scratch (spec §5.4): a `post_list` block's
    # own save/destroy, and a page move or reorder, both call this rather than
    # `sync`ing one post at a time, because either can hand a post its first
    # canonical page, take it away, or move it to a *different* page than the
    # one that just changed -- something a single record's own callback has
    # no way to know about.
    #
    # `content_type` is `nil` for "every post" (a page move/reorder can shift
    # tree order under listings of any type, and a content-type-less
    # post_list block matches every type itself) -- `Post.all`, not a
    # `where(content_type: nil)` that would compile to a no-op the way
    # `ContentBlock#listed_posts` warns against.
    #
    # `includes(:tags)` avoids an N+1 in `ContentBlock#lists?`'s tag check
    # across every post_list block `canonical_page` walks per post.
    def sync_posts(content_type)
      scope = content_type ? Post.where(content_type: content_type) : Post.all
      scope.includes(:tags).find_each { |post| sync(post) }
    end

    def rebuild!
      PublicPath.transaction do
        PublicPath.delete_all
        root = Page.find_by(parent_id: nil)
        sync_subtree(root) if root
        sync_posts(nil)
      end
    end

    def compute_path(record, locale)
      case record
      when Page then page_path(record, locale)
      when Post then post_path(record, locale)
      end
    end

    # The first page, in tree order (depth-first by sibling position), with a
    # post_list block that lists `post` (spec §5.3) -- "first" meaning the
    # one whose own position, then its parent's, then its parent's parent's
    # and so on up to the root, sorts lowest, which is exactly a depth-first
    # walk from the root without actually performing one: `self_and_ancestors`
    # (closure_tree, root last) reversed puts the root's position first and
    # this page's own last, so comparing those arrays lexicographically ranks
    # an earlier branch ahead of a later one at whichever ancestor they
    # diverge, and only falls through to a deeper `position` when every
    # shallower one ties -- which happens only between a page and its own
    # descendant, never between two different pages, since sibling `position`
    # values are unique (closure_tree's own invariant).
    #
    # Every post_list block is checked, not just the ones on already-synced
    # pages: this is also what a block's own save/destroy calls (via
    # `sync_posts`), where nothing about the page tree changed at all.
    def canonical_page(post)
      pages = ContentBlock.post_list.includes(:page).select { |block| block.lists?(post) }.map(&:page).uniq
      pages.min_by { |page| page.self_and_ancestors.reverse.map { |p| p.position.to_i } }
    end

    # A post's path is its canonical listing page's current path, then `/`,
    # then its own slug -- nil (no URL) when it has no canonical page, or that
    # page itself currently has no path (mid-move, or a draft-chain gap the
    # resolver's publication check handles, not this one -- §5.3 is explicit
    # that publication is ignored here).
    def post_path(post, locale)
      page = canonical_page(post)
      segment = post.public_send(Mobility.normalize_locale_accessor(:slug, locale))
      parent_path = page && current_path(page, locale)
      return nil if parent_path.nil? || segment.blank?

      parent_path == "/" ? "/#{segment}" : "#{parent_path}/#{segment}"
    end

    # The root is exempt from needing a slug of its own: it contributes no
    # segment and its path is "/" by design (see `Page#validates :slug`).
    # Every other page's path is its parent's path plus its own segment, so a
    # blank segment or a parentless-but-not-root page (mid-move, before the
    # closure_tree callback that fixes `parent_id` up has run) both come back
    # nil rather than silently landing on the parent's own address -- the
    # two-pages-one-URL collision `cached_paths` used to allow is now something
    # `HasPublicPaths`'s validation and the `(locale, path)` unique index both
    # refuse outright, so nil here is "no URL yet", never "borrow one".
    def page_path(page, locale)
      return "/" if page.parent_id.nil?

      segment = page.public_send(Mobility.normalize_locale_accessor(:slug, locale))
      parent_path = current_path(page.parent, locale)
      return nil if segment.blank? || parent_path.nil?

      parent_path == "/" ? "/#{segment}" : "#{parent_path}/#{segment}"
    end

    # Moves the record's current row to `path` in `locale`: the old current
    # row stays behind as a redirect; a redirect row already holding `path`
    # (any record's) is dropped so the address can be reused; no path at all
    # removes the record's rows for that locale, since there is nowhere left
    # to redirect them to.
    #
    # `update_columns` on the outgoing row, not `update` -- the same reason
    # `Page#write_cached_paths` used it: this runs once per record per sync,
    # from inside a save's `after_save`, and re-entering callbacks or
    # validations on a row nobody edited would be both wasted work and a risk
    # of failing a save that was never actually invalid.
    def write(record, locale, path)
      current = PublicPath.current.find_by(record: record, locale: locale)
      return if current&.path == path

      if path.nil?
        PublicPath.where(record: record, locale: locale).delete_all
      else
        current&.update_columns(current: false, updated_at: Time.current)
        PublicPath.redirects.where(locale: locale, path: path).delete_all
        PublicPath.create!(record: record, locale: locale, path: path, current: true)
      end
      announce(record, locale, current&.path, path)
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
