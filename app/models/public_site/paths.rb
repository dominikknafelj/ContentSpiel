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

    # Reported, never raised: see `copy_of_post_came_into_force`.
    AddressTaken = Class.new(StandardError)

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
    #
    # `rows: true` judges a post by the tags of its ROWS, whatever copy it
    # has: the address it WOULD have once those tags are published. That is
    # what `Publishing::PublishChanges` and `Posts::Save` ask before they take
    # a copy, so that a clash is refused instead of found afterwards
    # (`Post#address_free_as_typed?`).
    def compute(record, rows: false)
      case record
      when Page then page_paths(record, current_paths("Page", [ record.parent_id ].compact).fetch(record.parent_id, {}))
      when Post then post_paths([ record ], rows: rows).fetch(record)
      else Locales.enabled.index_with { nil }
      end
    end

    def sync(record)
      record.is_a?(Post) ? write_posts([ record ]) : write_all({ record => compute(record) })
    end

    # A page and everything below it, in a number of statements that doesn't
    # depend on how many pages that is: the pages below in one query, their
    # stored rows (and the parent's, which the top page hangs off) in another,
    # every path worked out in memory top-down, one lookup of the addresses
    # other records hold, and then only the rows that differ written, a set at
    # a time (`write_all`).
    #
    # Each page's path is built from the path its parent will actually *hold*
    # when this call is done -- never from the parent's stored row, which is
    # about to be replaced, and never from a path the parent wants but won't
    # get. That takes two passes: the first works every path out as if every
    # page got the one it wants, which is what says which addresses to ask
    # `held_by_others` about -- so `held` is computed for that optimistic set,
    # which can name an address a page stops wanting once its parent yields:
    # too cautious at worst, never too permissive, since every address the
    # second pass can hand out was asked about; the second (`settle`) goes
    # top-down again and hands a page's children only the paths that page
    # keeps -- not nil, not
    # another record's live address, not already given to an earlier page of
    # the pass. A page that has to yield keeps the path it wanted in what
    # `write_all` is handed (so it is treated as a yield and keeps its
    # redirects), and everything below it comes out nil: a page under one
    # without an address has none ("no URL yet, never borrow one", see
    # `page_path`), which is what keeps a yielder's children from being
    # written inside the URL space of the record that holds the address.
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

      PublicPath.transaction do
        stored = current_rows("Page", [ page.parent_id, *pages.map(&:id) ].compact)
        above = stored.filter_map { |(_, id, locale), (_, path)| [ locale, path ] if id == page.parent_id }.to_h

        wanted = settle(pages, { page.parent_id => above })
        held = held_by_others(changes_between(wanted, stored))
        write_all(settle(pages, { page.parent_id => above }, held: held), stored: stored, held: held)
      end
    end

    # `{ page => { locale => path } }` for `pages` (top-down: every page
    # after its parent), each from the paths its parent keeps; `kept` starts
    # as `{ parent id => { locale => path } }` for what the top page hangs
    # off. Without `held` every page keeps what it wants. With it (`{ [locale,
    # path] => [record type, record id] }`, the live addresses of other
    # records) a page keeps a path only when nobody else holds it and no
    # earlier page of the pass was given it, and its children are built from
    # what it keeps.
    def settle(pages, kept, held: nil)
      given = Set.new
      pages.index_with do |page|
        paths = page_paths(page, kept.fetch(page.parent_id, {}))
        kept[page.id] = paths.each_with_object({}) do |(locale, path), keeps|
          next if path.nil?
          next if held && (held.fetch([ locale.to_s, path ], [ "Page", page.id ]) != [ "Page", page.id ] || !given.add?([ locale.to_s, path ]))

          keeps[locale.to_s] = path
        end
        paths
      end
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
    # their tags (`includes(:tags)`, which the tag check of `Publishing
    # ::Listing.lists?` reads for a post that is judged by its rows; one with
    # a published copy is judged by the copy's, read for the whole batch in
    # one statement), `canonical_pages` for the whole batch at once, those
    # pages' current paths, the posts' stored rows, and then the writes for
    # whatever differs.
    def sync_posts(content_type)
      scope = content_type ? Post.where(content_type: content_type) : Post.all
      scope.includes(:tags).find_in_batches { |posts| write_posts(posts) }
    end

    # The addresses of these posts, each written with THE PAGE THAT GIVES IT
    # (`listed_on_id` of its current rows): the one fact about a post's
    # address that cannot be read back from the records afterwards, because
    # which page listed a post "until a moment ago" is gone once the block,
    # the copy or the tag that said so has changed.
    def write_posts(posts)
      hosts = canonical_pages(posts)
      write_all(post_paths(posts, hosts: hosts), hosts: hosts)
    end

    # `sync_posts` for every content type the listing blocks on `pages` and on
    # everything below them list: what has to be re-derived when something
    # about those pages changed that `canonical_page` ranks listing pages by
    # (their place in the tree, a live chain, the trash) -- the posts those
    # blocks list may have a new canonical page, here or elsewhere. Only
    # those: the order and publication of every page *outside* these
    # subtrees is as it was, so a post none of their blocks list keeps the
    # winner it had. A block with no content type lists every type, so one
    # such block means every post.
    def sync_posts_listed_under(pages)
      return if pages.empty?

      subtree_ids = Page.hierarchy_class.where(ancestor_id: pages.map(&:id)).select(:descendant_id)
      types = ContentBlock.listing.where(owner_type: Page.polymorphic_name, owner_id: subtree_ids).map { |block| block.settings_object.content_type }
      # And the types these pages' current COPIES list (drafts spec §5): a
      # published page lists what its copy lists, not what its rows do
      # (`canonical_pages`), so the posts to re-derive are the copies'. Both
      # are taken, for every page of the subtrees whatever its state, and not
      # `Publishing::Listing.blocks` (what is listed NOW): this is called from
      # the save that just changed the state, and the posts to look at are
      # the ones listed until a moment ago as much as the ones listed from now
      # on. Unpublishing a page moves its listing from the copy to the rows,
      # publishing it again moves it back (to the older copy, until
      # the copy taken by that save is announced: `published`), and a
      # trashed page lists nothing while its posts must be given to another.
      # Too many types is a sync that finds nothing to write; one too few is
      # a post left at an address nothing lists.
      types += Publishing::Listing.copied_types(page_ids: subtree_ids)
      types.include?(nil) ? sync_posts(nil) : types.uniq.each { |type| sync_posts(type) }
    end

    # The sweep for the one input no write announces: time. A scheduled page
    # becomes live (`Publishable#live?`) when `published_at` passes, and no
    # row is written at that moment -- but a live chain is the first thing
    # `canonical_page` ranks listing pages by, so the posts listed on that
    # page, or on any page below it, may belong under it from then on. This
    # re-derives them for every kept page that went live in `(since, now]`.
    #
    # Only the posts: a page's own path is its ancestors' slugs and its own
    # (`page_path`), whatever its publication, so there is no `sync_subtree`
    # to run here. A page that became live through a save (Publish) had its
    # posts synced by that save; sweeping it again finds nothing to change.
    #
    # Idempotent and unmarked: nothing records that a page was swept, the
    # caller's window simply overlaps the previous run's
    # (`PublicSite::SyncWentLiveJob` looks a day back every five minutes),
    # and a run with nothing to move reads and writes no row of
    # `public_paths` beyond the comparison. A page that went live before
    # `since` with no run in between (the job only runs where Solid Queue is
    # the adapter) is caught by the next sync that reaches its posts, or by
    # `rebuild!`.
    #
    # The same clock moves a second thing: a published copy taken with a time
    # ("Publish changes" at a time) comes into force when that time passes,
    # and with it the list blocks and tags addresses are derived from:
    # `sync_copies_went_live`, over the same window. For those a late or
    # missing run costs more than a delay: the public list is drawn from the
    # copy the moment its time has come, so until the sweep a post a new list
    # block lists has no address there (its link in that list leads nowhere
    # new), and one a removed block listed keeps an address that answers 404.
    # Where nothing sweeps (development, test) `bin/rails
    # public_paths:rebuild` is what catches up.
    def sync_went_live(since:, now: Time.current)
      sync_posts_listed_under(Page.kept.where(Page.arel_table[:published_at].gt(since)).where(published_at: ..now).to_a)
      sync_copies_went_live(since: since, now: now)
    end

    # A copy of `record` has come into force (`version`; `previous` is the
    # copy it follows, or nil): re-derive what it can change (drafts spec §5).
    # Called by `take!` of `Publishing::Version` for a copy in force at once,
    # inside its transaction, and by the sweep below for one whose time has
    # come. Nothing else announces a copy: a list block or a tag written in
    # the rows of a published record is not an input of any address until
    # then (`canonical_pages`), which is why a block's own sync
    # (`ContentBlock#sync_listed_post_paths`) and a tag's (`PostTag`) find
    # nothing to move for such a record.
    #
    # A post: its own address (its published tags decide which list holds
    # it). A page: the posts of every content type its list blocks name, in
    # this copy and in the one before, since a type the older copy listed and
    # this one does not is exactly a post that has to leave; a block with no
    # type lists every type, so every post. A page neither of whose copies
    # lists posts changes no address.
    #
    # In a save that publishes (`Pages::Save`, `Posts::Save`), the record's
    # own `after_save` sync ran BEFORE the copy was taken: for a first
    # publication it read the rows (there was no copy), and for a publication
    # after an unpublish the older copy, which was in force again from the
    # moment `published_at` was set. This call is what corrects that second
    # case with the new copy.
    #
    # WHICH OLDER STATE THE STORED ADDRESSES REFLECT is not always `previous`.
    # A copy taken with a time comes into force by the clock, and until the
    # sweep has run (five minutes in production, never where nothing sweeps)
    # the addresses still say what the copy BEFORE it listed. So a `previous`
    # that was taken with a time is not trusted to have been swept: the copy
    # before it is read as well, and so on back to the first copy that was in
    # force the moment it was taken (announced by `take!`, in its
    # transaction, so the addresses did reflect it). When the copies run out
    # first, the page had none before a scheduled one and listed what its
    # ROWS listed (a page written around the services); what that was is
    # recorded nowhere, so every post is re-derived. A type too many is a
    # sync that writes nothing. A post needs none of this: its address is
    # derived from what is in force now.
    def published(record, version, previous)
      return sync(record) if record.is_a?(Post)

      copies = reflected_copies(record, version, previous)
      types = copies.flat_map { |copy| Publishing::Listing.types_of(copy) }
      # The chain ended on a copy taken with a time: there is none before
      # it, the addresses reflect the page's rows as they were at some moment
      # nobody recorded, and so every post is looked at.
      types << nil if scheduled?(copies.last)
      types.include?(nil) ? sync_posts(nil) : types.uniq.each { |type| sync_posts(type) }
    end

    # `version`, `previous`, and behind a copy that was taken with a time the
    # one before it, newest first (see `published`). One query per scheduled
    # copy in the chain: none for a page that is always published at once.
    def reflected_copies(record, version, previous)
      copies = [ version ]
      copy = previous
      while copy
        copies << copy
        break unless scheduled?(copy)

        copy = older_copy(record, copy)
      end
      copies
    end

    # Taken with a time of its own: in force by the clock, not by a write.
    def scheduled?(copy) = copy.live_at > copy.created_at

    def older_copy(record, copy)
      Publishing::Version.of(record).where(Publishing::Version.arel_table[:number].lt(copy.number)).order(number: :desc).first
    end

    # A scheduled copy of a POST has come into force (the sweep's half of
    # `published`): its address is derived again, as `sync` does. The check
    # that can REFUSE a clash runs when the change is scheduled
    # (`Publishing::PublishChanges`, `HasPublicPaths#address_free_as_typed?`);
    # this is what remains when another record took the address in between.
    # A sweep can refuse nothing, and `public_paths` equals a full rebuild
    # whatever happens, so the post YIELDS like any other clash
    # (`yield_to_holder`) and has no address until someone resolves it: a
    # slug, a tag or the other record changed. What is added here is that the
    # person running the site learns of it: the clash is reported once per
    # copy through `Rails.error.report`, with the record and the address it
    # wanted, and nothing of its content. (Not the address it lost: another
    # sync of the same run may have taken that already.)
    #
    # "Once" is kept by the cache, since the sweep looks at the same copy
    # every five minutes for a day: where the cache keeps nothing, each run
    # in which the post still wants the taken address reports again.
    def copy_of_post_came_into_force(post, version)
      desired = compute(post)
      stored = current_rows("Post", [ post.id ])
      changes = changes_between({ post => desired }, stored)
      held = held_by_others(changes)
      clashing = changes.select { |change| change.to && held.key?([ change.locale, change.to ]) }
      write_all({ post => desired }, stored: stored, held: held, hosts: canonical_pages([ post ]))
      return if clashing.empty?
      return unless Rails.cache.write("public_paths/clash/#{version.id}", true, unless_exist: true, expires_in: 2.days)

      Rails.error.report(AddressTaken.new("a scheduled change came into force onto an address another record holds"), handled: true,
        context: { record_type: "Post", record_id: post.id, version_id: version.id,
                   addresses: clashing.map { |change| { locale: change.locale, wanted: change.to } } })
    end

    # `published` for the copies no write announces: every copy that was
    # taken with a time of its own (`live_at` after `created_at`; a copy in
    # force at once was announced by `take!`, and has the two equal) and
    # whose time is in `(since, now]`. Each is compared with the copy before
    # it, by number.
    #
    # Idempotent and unmarked like the sweep above, and for the same reason:
    # a copy swept before finds nothing to write. A run in which no copy came
    # into force reads `published_versions` once and nothing else. A trashed
    # record's copy is skipped: it has no address and its blocks are no
    # candidates, and restoring it re-derives both from the copy then in
    # force.
    def sync_copies_went_live(since:, now: Time.current)
      versions = Publishing::Version.arel_table
      came = Publishing::Version.where(versions[:live_at].gt(since)).where(live_at: ..now)
        .where(versions[:live_at].gt(versions[:created_at])).includes(:record).order(:id)
      came.each do |version|
        next if version.record.nil? || version.record.trashed?

        next copy_of_post_came_into_force(version.record, version) if version.record.is_a?(Post)

        # A page with no copy before this one listed what its ROWS list until
        # this copy's time came: `published` looks at those types too.
        published(version.record, version, older_copy(version.record, version))
      end
    end

    # Bumps the public content version whatever it finds: this is the repair
    # for a table suspected wrong, so what the site served from it is suspect
    # too.
    def rebuild!
      PublicPath.transaction do
        PublicPath.delete_all
        PublicSite.bump_version!
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
    def post_paths(posts, rows: false, hosts: nil)
      pages = hosts || canonical_pages(posts, rows: rows)
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
    #    moment, so posts don't move onto a scheduled listing page the instant
    #    it goes live: `sync_went_live` moves them, run every five minutes by
    #    `PublicSite::SyncWentLiveJob` where Solid Queue is the adapter
    #    (production), and elsewhere the next sync that reaches them does (a
    #    save of that page or an ancestor that changes one of its URL inputs,
    #    a write to a listing block, a save of the post that changes one of
    #    its own, or `rebuild!`). Until then they stay at the published
    #    listing they already had, which keeps serving them; the ETag already
    #    changes at go-live (`PublicSite.content_version`), so the page itself
    #    isn't served stale.
    #
    # 2. specificity -- a block naming the post's content type beats an
    #    unfiltered one, then a block whose tag the post carries beats one
    #    with no tag filter. This is what keeps a homepage "latest posts"
    #    teaser (unfiltered, and on the root, which always comes first in tree
    #    order) from taking every post's URL away from /blog. (A block that
    #    names a *different* type or a tag the post lacks isn't a candidate at
    #    all -- `lists?` already said no.) Which blocks there are and which
    #    tags the post carries are both read AS PUBLISHED: see
    #    `canonical_pages`.
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
    # `sync_posts`), where nothing about the page tree changed at all. (On a
    # published page that has a copy that call now finds nothing to move:
    # the block is no candidate until the page's changes are published.)
    def canonical_page(post) = canonical_pages([ post ]).fetch(post)

    # `canonical_page` for several posts in ONE pass: `{ post => page or nil }`.
    # The listing blocks, their owners, every candidate's ancestry, the tags
    # the blocks filter by and the posts' published copies are loaded once (a
    # constant number of queries however many posts, blocks or pages there
    # are), then each post is ranked among the blocks that list it. The
    # New post dialog asks for every creatable type's listing page at once.
    def canonical_pages(posts, rows: false)
      # The list blocks AS PUBLISHED (`Publishing::Listing.blocks`, drafts
      # spec §5): a published or scheduled page that has a copy lists what
      # its current copy lists, so a list block changed, added or deleted in
      # its rows moves no address until the page is published -- the public
      # list is drawn from that same copy, and a post in it must open. Every
      # other page (a draft, a page written around the services) lists what
      # its rows do, as before.
      #
      # Every block whose type has the `lists_posts` capability -- only a
      # `Page` owner is a candidate at all (open-types spec §4.1 lets other
      # records own blocks too, but none render a listing of their own posts
      # today). A block on a trashed page isn't a candidate either (trash spec
      # §5.2): its posts move to the next-best listing, or lose their URL,
      # and come back here when the page is restored.
      #
      # Each block's `owner` is the page's ROW, read now, whichever of the
      # two its blocks came from: publication, the tree and the trash are
      # immediate (they are not in a copy), and they are what the ranking
      # below reads -- and the row is what this method answers.
      candidates = Publishing::Listing.blocks
      chains = ancestry_chains(candidates.map(&:owner).uniq)
      # The tag each filtered block names, by id, found once for all of them.
      tags = Publishing::Listing.filter_tags(candidates)
      # Each post is judged by its tags as published, for the same reason: a
      # published post that has a copy by the copy's tags, any other (a
      # draft, an unsaved one, one written around the services) by its rows'.
      # Only the tags: the post's type, slug, publication and trash state are
      # read from `post` itself by everything else here.
      # (`rows: true`: every post by its rows' tags, see `compute`.)
      views = posts.zip(rows ? posts : Publishing.published_all(posts)).each_with_object({}.compare_by_identity) { |(post, view), all| all[post] = view }

      posts.index_with do |post|
        view = views.fetch(post)
        best = candidates.select { |block| Publishing::Listing.lists?(block, view, tags: tags) }.min_by do |block|
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
    # what differs from `stored` (their rows as `current_rows` reads them)
    # and yielding to `held` (see `held_by_others`) -- both read here when
    # the caller hasn't already -- in a number of statements that doesn't
    # depend on how many records or rows there are.
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
    # record may take the address another record of this same call (one
    # batch) has just left (one address per locale, redirects included).
    #
    # `hosts` (`{ post => page }`, `canonical_pages`' answer) is written with
    # a post's row as `listed_on_id`. A row is only written when its path
    # changes, and that is enough: a post's path begins with its host's, and
    # a current path belongs to one page, so the host cannot change under a
    # path that stays (`assert_parity` in the paths test compares the column
    # with a rebuild's after every write path).
    #
    # `update_all`, `delete_all` and `insert_all!`, never a model save: this
    # runs from inside another record's `after_save`, and re-entering
    # callbacks or validations on a row nobody edited would be both wasted
    # work and a risk of failing a save that was never actually invalid.
    # `insert_all!`, with the bang: a path that did turn out to be taken is
    # an exception, not a row silently left out.
    #
    # The table has no model callbacks, so this is also where a changed
    # address moves the public content version (`PublicSite.bump_version!`,
    # called inside the transaction below and so deferred to its commit):
    # when a row of a *live* record was written --
    # `Publishable#live?`, its own publication time, whatever its ancestors
    # or the trash say. The rows of a draft or a scheduled record move
    # nothing, because nothing published reads them: the resolver answers 404
    # for the record, a listing leaves it out, the navigation and the sitemap
    # skip it, and an internal link to it renders as plain text
    # (`RichText::BuiltIns.render_internal_link`). Preview does read them, and
    # is never served from the render cache for that reason
    # (`RichText::Document#to_html`). A record that stops or starts being
    # live in the same save is bumped by its own `after_commit`, and one that
    # goes live by the clock by `PublicSite.content_version`'s publication
    # times.
    def write_all(desired, stored: nil, held: nil, hosts: {})
      records = desired.keys
      return if records.empty?

      stored ||= current_rows(records.first.class.polymorphic_name, records.filter_map(&:id))
      changes = changes_between(desired, stored)
      return if changes.empty?

      type = records.first.class.polymorphic_name
      PublicPath.transaction do
        # Inside the transaction, so the bump waits for *this* commit even
        # when the caller has none open (a tag service's sync after its own
        # commit, `PostTag`'s `after_commit`, `SyncWentLiveJob`). Called
        # ahead of it, the counter would move at once and the rows commit
        # afterwards: a request in between would render the old addresses
        # under the new version, and nothing would bump again.
        PublicSite.bump_version! if changes.any? { |change| !change.record.respond_to?(:live?) || change.record.live? }
        held ||= held_by_others(changes)
        given = Set.new
        moved, rest = changes.partition { |change| change.to && !held.key?([ change.locale, change.to ]) && given.add?([ change.locale, change.to ]) }
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
            { record_type: type, record_id: change.record.id, locale: change.locale, path: change.to, current: true,
              listed_on_id: hosts[change.record]&.id, created_at: now, updated_at: now }
          end)
        end

        (gone + moved).each { |change| announce(change.record, change.locale, change.from, change.to) }
      end
    end

    # What differs: one `Change` per record and locale whose path in
    # `desired` is not the one its current row in `stored` holds, in the
    # order of `desired`.
    def changes_between(desired, stored)
      desired.flat_map do |record, paths|
        type = record.class.polymorphic_name
        paths.filter_map do |locale, path|
          row_id, from = stored[[ type, record.id, locale.to_s ]]
          Change.new(record, locale.to_s, row_id, from, path) unless from == path
        end
      end
    end

    # `{ [locale, path] => [record type, record id] }` for the wanted paths
    # that are some *other* record's live address and will still be after
    # this call -- a current row that one of these changes is itself moving
    # away, or deleting, holds nothing any more. One query.
    #
    # The record's own save never gets this far with such a path --
    # `HasPublicPaths#public_paths_are_available` turns it into a validation
    # error first (spec §5.2), and where the validation cannot see the path
    # yet, the service asks again before it lets the write stand
    # (`HasPublicPaths#address_free_as_typed?`: `Posts::Save`, once a new
    # tag has its id and before a first copy is taken, and
    # `Publishing::PublishChanges`, before the copy that publishes a post's
    # tags) -- so a hit here means the sync was triggered by a *different*
    # record's write, or by the clock (a copy of a post that came into force
    # at its time, `sync_copies_went_live`: it was asked when it was
    # scheduled, and an address taken since cannot be refused by a sweep):
    # a post_list block saved or destroyed
    # (`ContentBlock#sync_listed_post_paths`), a page saved, moved or
    # reordered (`Page#sync_public_paths`, including a cascade into its
    # descendants), a tag added or removed (`PostTag#sync_post_paths`), or a
    # language enabled. E.g. page /blog/team plus post "team" living at /team
    # via a homepage listing: removing that homepage block moves the post
    # onto /blog/team, which the page holds.
    def held_by_others(changes)
      wanted = changes.filter_map(&:to).uniq
      return {} if wanted.empty?

      leaving = changes.filter_map(&:row_id).to_set
      pairs = changes.filter_map { |change| [ change.locale, change.to ] if change.to }.to_set
      PublicPath.current.where(path: wanted).pluck(:id, :locale, :path, :record_type, :record_id)
        .each_with_object({}) do |(row_id, locale, path, type, id), held|
          held[[ locale, path ]] = [ type, id ] if !leaving.include?(row_id) && pairs.include?([ locale, path ])
        end
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
    # again once a later sync gives it one.
    #
    # An interim state, known and accepted: once the clash is gone, nothing
    # looks again on the yielder's behalf. It gets its address back at the
    # next sync that reaches it -- a save of it that changes one of its URL
    # inputs, any of the triggers above -- or from `bin/rails
    # public_paths:rebuild`, which is the fix when a record is found without
    # an address; a save that changes no input (most autosaves) does not
    # look. The other side of the same condition: the yielder's editor is not
    # told of the clash on every autosave either, since the availability
    # validation is skipped for a save that changes no input. Logged, since
    # nothing on screen says why the record vanished from that address.
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
