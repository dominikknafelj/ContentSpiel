# Derives and stores every public URL (spec §5.4). Called from model
# callbacks (HasPublicPaths) rather than from services on purpose: CS
# Studio, seeds and fixtures-built data all save through ActiveRecord, and
# every one of those writes has to leave the URL table correct.
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
    # own save/destroy, and a page save (including a move, reorder or publish
    # -- `Page#resync_listed_posts`, for the types its subtree's blocks list),
    # both call this rather than `sync`ing one post at a time, because either
    # can hand a post its first canonical page, take it away, or move it to a
    # *different* page than the one that just changed -- something a single
    # record's own callback has no way to know about.
    #
    # `content_type` is `nil` for "every post" (a content-type-less
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
    # `sync_subtree` -- from ever giving it one back; `write(record, locale,
    # nil)` deletes the record's current row *and* its redirects for that
    # locale. A trashed page's descendants follow without a check of their
    # own: `page_path` finds no current path for their parent and returns nil.
    # Restoring is the same save in reverse: `trashed_at` cleared, the
    # model's own `after_save` sync writes the rows afresh (old redirects are
    # not resurrected -- they were deleted, not demoted).
    def compute_path(record, locale)
      return nil if record.respond_to?(:trashed?) && record.trashed?

      case record
      when Page then page_path(record, locale)
      when Post
        if record.definition.nil?
          Rails.logger.warn("[public_paths] Post##{record.id} gets no #{locale} URL: " \
            "#{record.content_type.inspect} isn't a registered content type")
          nil
        else
          post_path(record, locale)
        end
      end
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
    #    goes live, only at the next sync that reaches them (any write to that
    #    page, its blocks or the posts, or `rebuild!`). Until then they stay
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
    def canonical_page(post)
      # `ContentBlock.listing` is every block whose type has the
      # `lists_posts` capability -- only a `Page` owner is a candidate at
      # all (open-types spec §4.1 lets other records own blocks too, but
      # none render a listing of their own posts today).
      # A block on a trashed page isn't a candidate either (trash spec §5.2):
      # its posts move to the next-best listing, or lose their URL, and
      # come back here when the page is restored.
      blocks = ContentBlock.listing.includes(:owner).select do |block|
        block.owner.is_a?(Page) && !block.owner.trashed? && block.lists?(post)
      end
      chains = blocks.map(&:owner).uniq.index_with { |page| page.self_and_ancestors.to_a.reverse }

      best = blocks.min_by do |block|
        chain = chains[block.owner]
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

    # A post's path is its canonical listing page's current path, then `/`,
    # then its own slug -- nil (no URL) when it has no canonical page, or that
    # page itself currently has no path (mid-move). A canonical page that is
    # unpublished (only chosen when no published candidate exists, see
    # `canonical_page`) still gives the post a path: the resolver's
    # publication check is what keeps it off the public site.
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
    #
    # A `path` another record's *current* row already holds is skipped rather
    # than written: see `yield_to_holder`.
    def write(record, locale, path)
      current = PublicPath.current.find_by(record: record, locale: locale)
      return if current&.path == path
      return yield_to_holder(record, locale, path, current) if path && held_by_another?(record, locale, path)

      if path.nil?
        PublicPath.where(record: record, locale: locale).delete_all
      else
        current&.update_columns(current: false, updated_at: Time.current)
        PublicPath.redirects.where(locale: locale, path: path).delete_all
        PublicPath.create!(record: record, locale: locale, path: path, current: true)
      end
      announce(record, locale, current&.path, path)
    end

    # Whether `path` is some *other* record's live address in `locale`. The
    # record's own save never gets this far with such a path --
    # `HasPublicPaths#public_paths_are_available` turns it into a validation
    # error first (spec §5.2) -- so a hit here means the sync was triggered
    # by a *different* record's write: a post_list block saved or destroyed
    # (`ContentBlock#sync_listed_post_paths`), a page saved, moved or
    # reordered (`Page#sync_public_paths`, including a cascade into its
    # descendants), a tag added or removed (`PostTag#sync_post_paths`), or a
    # language enabled. E.g. page /blog/team plus post "team" living at /team
    # via a homepage listing: removing that homepage block moves the post
    # onto /blog/team, which the page holds.
    def held_by_another?(record, locale, path)
      PublicPath.current.where(locale: locale, path: path)
        .where.not(record_type: record.class.polymorphic_name, record_id: record.id).exists?
    end

    # The record that did not ask for this sync goes without a URL in this
    # locale rather than raising: the unique index would otherwise throw
    # `RecordNotUnique` out of somebody else's save -- a 500 on a block
    # removal the editor can't get past, or, from `PostTag`'s `after_commit`,
    # an exception after the data is already committed. Its current row (if
    # it had one) is deleted, not demoted: nothing else may claim that old
    # address as a redirect *to* a record with no address. Its existing
    # redirect rows are kept; they resolve to a 404 while it has no current
    # row (`Resolver#from_row` finds no target) and start 301ing again once a
    # later sync gives it one -- after the clash is removed, the next sync
    # that reaches the record (its own save, or any of the triggers above,
    # or `rebuild!`) restores the URL. Logged, since nothing on screen says
    # why the record vanished from that address.
    def yield_to_holder(record, locale, path, current)
      Rails.logger.warn("[public_paths] #{record.class.polymorphic_name}##{record.id} gets no #{locale} URL: " \
        "#{path} is already another record's current path")
      return if current.nil?

      current.delete
      announce(record, locale, current.path, nil)
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
