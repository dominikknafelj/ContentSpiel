class Page < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable
  include Trashable

  localized_slug scope: :parent_id

  # A root child's slug is the whole first path segment after the domain --
  # exactly where CS Studio lives too (cs-studio spec §3). Checked here,
  # alongside the other slug validations above, rather than inside the
  # shared LocalizedSlug concern: this rule is specific to a page's position
  # in *this* tree (only a root child's slug becomes a top-level segment;
  # Post has no tree position and no equivalent rule).
  validate :slug_not_reserved_for_admin

  # closure_tree 9.8: `has_closure_tree` builds the PageHierarchy model and the
  # parent/children/ancestors/descendants associations on top of the
  # `page_hierarchies` closure table.
  #
  # `order:` + `numeric_order: true` hand closure_tree the `position` column --
  # it renumbers siblings itself on create, move and reorder, which is what the
  # admin's drag-to-reorder needs.
  #
  # `dependent:` defaults to `:nullify`, which silently promotes a destroyed
  # page's children to roots -- both a cascade we don't want and a violation of
  # the one-root rule. `:restrict_with_error` disables it; `ensure_no_children`
  # below is what actually reports the refusal, in this app's wording.
  has_closure_tree order: "position", numeric_order: true, dependent: :restrict_with_error

  # HasPublicPaths adds the `public_paths` association, `full_path`, a
  # validation and one `before_save` that only reads the pending changes
  # (`remember_url_inputs_change`), so this include's own position isn't
  # load-bearing the way `after_save :sync_public_paths` below is. It sits
  # here, right after the tree is set up, because the paths it computes are
  # built from the ancestor chain `has_closure_tree` provides.
  include HasPublicPaths

  # What a page's URLs, and the URLs of the posts its subtree lists, are
  # built from (see `HasPublicPaths` for everything that is synced by
  # another writer instead):
  # - `slug`, in every language: the page's own segment, and so a prefix of
  #   every descendant's path;
  # - `parent_id`: the path it hangs off;
  # - `trashed_at`: a trashed page has no URL, nor has anything below it;
  # - `position` and `published_at`: no part of a page's own path, but what
  #   `PublicSite::Paths.canonical_page` ranks listing pages by (tree order
  #   and a live chain), so they decide which page the posts listed in this
  #   subtree live under. `position` as *requested*: the question is asked
  #   before the row is written, so the renumbering `Page::TreeRanking` does
  #   afterwards plays no part in it.
  # `trash_root_id` and `trashed_by_id` are bookkeeping no path reads.
  url_inputs_are :slug, :parent_id, :position, :published_at, :trashed_at

  # Model-specific concern for the "move to rank N" logic (spec §3), included
  # here -- right after `has_closure_tree` -- so its `after_save
  # :place_among_siblings` (app/models/page/tree_ranking.rb) is declared, and
  # therefore runs, before `after_save :sync_public_paths` below: a move or
  # reorder can change which page is *canonical* for a post_list block
  # elsewhere in the tree (`PublicSite::Paths.canonical_page` ranks pages by
  # sibling `position`), so paths must not be (re)computed until every
  # sibling's position has been written out by `place_among_siblings`. Include
  # order is what fixes callback order here (both are `after_save`s declared
  # on `Page` itself, so Rails would otherwise just run them in declaration
  # order) -- moving this include below `after_save :sync_public_paths` would
  # silently flip that order back and let canonical-page resyncs read stale
  # positions.
  include Page::TreeRanking

  # jsonb columns holding one value per locale; reading or writing them goes
  # through the current Mobility.locale. `hero_alt` is the alt text for
  # whichever hero image the page's theme renders, translated for the same
  # reason every other piece of editor-facing copy here is.
  translates :title, :slug, :subtitle, :meta_title, :meta_description, :hero_alt

  # Which version of the original each translation was saved against
  # (translation helpers spec §3.2). Never `slug`: it's generated per
  # language, not translated from the original's.
  include Translations::Tracker
  include TitleSearch
  tracks_translations

  # A page's body is an ordered list of blocks; the renderer walks them in
  # `position` order and dispatches on each one's `block_type`. `as: :owner`
  # because `ContentBlock#owner` is polymorphic (open-types spec §4.1) --
  # only `Page` uses it today, but a future owner can hold blocks the same
  # way.
  #
  # Declared before the association on purpose: `dependent: :destroy` below
  # destroys the blocks one statement at a time in `position` order, and a
  # section deleted before the blocks in it is refused by the foreign key
  # (`content_blocks.section_id`, NO ACTION). So the blocks that sit in a
  # section go first. They are taken from the loaded association, so they are
  # the very objects `Trash::Purge` holds and refreshes afterwards; the pass
  # below meets them again already destroyed, which deletes nothing.
  before_destroy { content_blocks.select(&:section_id).each(&:destroy!) }
  has_many :content_blocks, -> { order(:position) }, as: :owner, dependent: :destroy

  # The admin edits a page's blocks inside the page's own form (page-tree design
  # spec section 5), which is Rails' nested attributes underneath:
  # `allow_destroy` is what each row's "Remove" checkbox writes to.
  #
  # `reject_if` is what lets that form carry a permanently-present blank row to
  # add a block with: without it, every save of a page would store one more
  # empty block. A row is "not filled in" when no block type was picked -- and
  # only for a new row, since an existing block always submits its own type and
  # must still be updatable (or destroyable) through the same call.
  accepts_nested_attributes_for :content_blocks, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["block_type"].blank? }

  # The page's hero image (design spec §3.3): a reference to a library
  # `Media::Asset`, not an attachment of its own -- Task 4's data migration
  # (`MoveImagesIntoMediaLibrary`) moved every former `has_one_attached
  # :hero_image` onto this column, re-using the same blobs. The per-use alt
  # text stays on the page (`hero_alt`, translated); the asset only supplies
  # its own default (`Media::Asset#alt_text`). The FK is `on_delete:
  # :restrict`, so an asset a page still shows can't be deleted out from
  # under it. `optional: true`: a page need not have a hero at all.
  belongs_to :hero_media_asset, class_name: "Media::Asset", optional: true

  # Which page an editor actually trashed (trash spec §3.1): set on this page
  # and every descendant that goes with it, so `Trash::Restore` can bring the
  # whole branch back together even though each row's own `trashed_at` is
  # identical and gives no ordering to restore by. `optional: true` -- a kept
  # page has no trash root at all, and the FK nullifies rather than restricts
  # so purging the root itself doesn't get blocked by its own descendants'
  # bookkeeping column.
  belongs_to :trash_root, class_name: "Page", optional: true

  # The two halves of a trashed branch (`Trash::Move`). A branch root is the
  # page the editor picked: its `trash_root_id` is its own id. A branch member
  # went with a root and names that root instead; a page with no
  # `trash_root_id` at all is neither. Neither scope looks at `trashed_at`:
  # the caller says `trashed` (or a read scope that does) beside it.
  scope :trash_roots, -> { where(arel_table[:trash_root_id].eq(arel_table[:id])) }
  scope :trash_branch_members, -> { where.not(trash_root_id: nil).where(arel_table[:trash_root_id].not_eq(arel_table[:id])) }

  # `validate: true`: an unknown value (a forged `page[page_type]`) is an
  # ordinary "is not included in the list" validation failure on the field,
  # for every caller of `Pages::Save`, instead of the `ArgumentError` a plain
  # enum raises on assignment (a 500 from a request).
  enum :page_type, { standard: 0, landing: 1 }, validate: true

  # "Titled" means *some* locale has a title, not "the locale that happens to
  # be ambient when this record is saved" -- a page may legitimately exist in
  # German before it is ever written in English, or vice versa. Before this
  # task, `validates :title, presence: true` got this right by accident:
  # Mobility's own global fallback plugin meant the plain reader returned
  # *some* locale's title regardless of which one was ambient. Now that plain
  # readers read literally (config/initializers/mobility.rb), the same
  # `validates :title, presence: true` would instead reject a fully-titled
  # page just because it was saved inside a `Mobility.with_locale(:de)` block
  # for an unrelated German-only edit -- so this reads the raw jsonb hash
  # directly rather than through Mobility, sidestepping the ambient locale
  # entirely.
  validate :title_present_in_any_locale

  # A page's path is its ancestors' slugs plus its own (`PublicSite::Paths.
  # page_path`), which drops a blank segment -- so a non-root page without a
  # slug would contribute nothing and land on its parent's path exactly,
  # meaning a slugless child of the root would answer to "/", the homepage's
  # own address.
  #
  # Before a slug-presence validation existed, that produced the
  # two-pages-one-URL bug: two pages then answered to one path, and the
  # lookup could only return one of them -- the other unreachable at any
  # address at all, while still being listed in the sitemap, with nothing the
  # admin could see deciding which one lost. All from a single missed field
  # on the page form, which reported no error anywhere.
  #
  # `LocalizedSlug#slug_present_in_every_enabled_locale` (registered by
  # `localized_slug scope: :parent_id` above) is what keeps a blank segment
  # from ever reaching `PublicSite::Paths` in the first place -- checked
  # per *enabled* locale rather than "some locale has one," since a slug has
  # no fallback the way a blank title does; `HasPublicPaths`'s own validation
  # (app/models/concerns/has_public_paths.rb) and the `public_paths (locale,
  # path)` unique index are what additionally catch two *different*,
  # non-blank slugs that would still resolve to the same address.
  #
  # The root is exempt because its slug is `""` by design (see
  # `PublicSite::Paths.page_path`): the homepage contributes no segment and
  # its path is "/" -- `generates_slugs?` below is what tells the shared
  # validation to skip it, the same guard `fill_blank_slugs` already uses.

  # `pages.position` is nullable because closure_tree is what fills it in,
  # after the first save -- so this cannot be a plain presence validation or no
  # page could ever be created. On an existing page the column is always set,
  # and a blank is only ever the admin clearing the input: without this,
  # closure_tree's `_ct_after_save` takes `.min` of the old and new values and
  # raises `ArgumentError: comparison of Integer with nil failed`, which
  # reaches the editor as a raw 422 instead of a form error.
  validates :position, presence: true, on: :update

  validate :only_one_root_page

  # Prepended so it runs ahead of the callbacks `has_closure_tree` installed:
  # closure_tree's own `_ct_before_destroy` tears down this page's hierarchy
  # rows before any later callback gets a say. Throwing :abort from the front
  # of the chain means nothing is touched at all.
  before_destroy :ensure_no_children, prepend: true

  # Declared *after* `has_closure_tree`, so it runs after closure_tree's own
  # `after_save` -- which is what creates and rebuilds the hierarchy rows
  # `PublicSite::Paths.sync_subtree` reads back to assemble the path.
  #
  # Only for a save that changed one of the page's URL inputs
  # (`url_inputs_are` above; a new page always). That is asked in a
  # `before_save` and not here with `saved_change_to_...?`: closure_tree's
  # `after_save` has reloaded the record by now, which clears those flags.
  # `slug` is compared as its whole translation hash, so a slug changed in
  # any one language counts. Everything else -- a title, the hero, the SEO
  # fields -- can't have changed a URL, and syncing for it re-derived every
  # descendant and every listed post inside each autosave's transaction.
  after_save :sync_public_paths

  # `AccessControl.preload_branches` leaves a snapshot of this page's
  # self-and-ancestor ids on the object (so rendering the tree checks
  # permissions without a closure query per row). A save can move the page
  # -- closure_tree rewrites its hierarchy rows in its own `after_save` --
  # and a reload is the explicit "read me afresh", so both drop the
  # snapshot: the next permission check reads the closure table again
  # instead of answering from where the page used to be.
  after_save :forget_preloaded_branch

  # The settings form's autosave base (live-editing spec §3.3). Moved whenever a
  # column of the page itself is about to change, and by nothing else: a `touch`
  # (every block write touches its page) runs no save callbacks, and
  # `update_columns` and `update_all` go around them on purpose
  # (`Translations::Confirm`'s bookkeeping must not make an open form stale).
  # So someone in the settings is refused only when the SETTINGS changed.
  # `Trash::Move#trash_descendants` and `Trash::Restore#restore_branch_members`
  # move descendants with `update_all`, so a descendant's base does not move on
  # trash and restore while the branch root's does: harmless, no settings value
  # changes.
  SETTINGS_BASE_IGNORES = %w[updated_at settings_changed_at].freeze
  before_save { self.settings_changed_at = Time.current if new_record? || (changed - SETTINGS_BASE_IGNORES).any? }

  def reload(...)
    forget_preloaded_branch
    super
  end

  private

  def forget_preloaded_branch
    ivar = AccessControl::Checker::PRELOADED_BRANCH_IDS
    remove_instance_variable(ivar) if instance_variable_defined?(ivar)
  end

  # The homepage's slug is "" by design (see `PublicSite::Paths.page_path`).
  def generates_slugs?
    parent_id.present?
  end

  def sync_public_paths
    return unless url_inputs_changed_by_save?

    PublicSite::Paths.sync_subtree(self)
    resync_listed_posts
  end

  # A page's own save can hand a post_list block a new position in the tree,
  # or a newly (un)published page chain, without the block itself changing at
  # all -- `sync_subtree` above already rewrote this page's (and its
  # descendants') paths for that, but every post any of *their* post_list
  # blocks list also needs its canonical page re-derived, since chain
  # publication and tree order -- not just this page's own path -- are what
  # `PublicSite::Paths.canonical_page` ranks candidates by (spec §5.3).
  #
  # Scoped to this subtree's own post_list blocks
  # (`PublicSite::Paths.sync_posts_listed_under`, which says why that is
  # enough), for every kind of save that gets here -- a slug, publish state,
  # a move, a reorder or the trash alike. The posts they list are re-derived
  # from scratch against every candidate in the tree, which covers both
  # "moved ahead of another listing, now canonical" and "moved behind it,
  # gave the posts back".
  def resync_listed_posts
    PublicSite::Paths.sync_posts_listed_under([ self ])
  end

  # Checked per enabled locale, the same granularity
  # `LocalizedSlug#slug_is_unused_in_every_locale` uses, so the admin form
  # marks whichever locale's tab actually collides -- an editor translating
  # a page one language at a time only typed the reserved value into one of
  # them.
  def slug_not_reserved_for_admin
    return unless parent&.root?

    ::Locales.enabled.each do |locale|
      accessor = ::Mobility.normalize_locale_accessor(:slug, locale)
      next unless public_send(accessor) == ContentSpiel::ADMIN_PATH

      errors.add(accessor, "is reserved for the admin")
    end
  end

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :title_present_in_any_locale`.
  def title_present_in_any_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h.values.all?(&:blank?)
  end

  # The tree has exactly one root: the homepage. Checked on update as well as
  # create, since detaching an existing child (`page.parent = nil`) would
  # otherwise mint a second root without ever creating a record.
  def only_one_root_page
    return unless parent_id.nil?

    scope = Page.where(parent_id: nil)
    scope = scope.where.not(id: id) if persisted?

    errors.add(:base, "a root page already exists") if scope.exists?
  end

  # Deleting a branch has to be deliberate: the admin removes the leaves first.
  def ensure_no_children
    return if children.empty?

    errors.add(:base, "cannot delete a page that still has children")
    throw :abort
  end
end
