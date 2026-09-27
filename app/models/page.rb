class Page < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable

  localized_slug scope: :parent_id

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

  # HasPublicPaths only adds the `public_paths` association, `full_path`, and
  # a validation -- no callback of its own, so this include's own position
  # isn't load-bearing the way `after_save :sync_public_paths` below is. It
  # sits here, right after the tree is set up, because the paths it computes
  # are built from the ancestor chain `has_closure_tree` provides.
  include HasPublicPaths

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

  # A page's body is an ordered list of blocks; the renderer walks them in
  # `position` order and dispatches on each one's `block_type`.
  has_many :content_blocks, -> { order(:position) }, dependent: :destroy

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

  has_one_attached :hero_image

  enum :page_type, { standard: 0, landing: 1 }

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
  # Before this validation existed, that produced the two-pages-one-URL bug:
  # two pages then answered to one path, and the lookup could only return one
  # of them -- the other unreachable at any address at all, while still being
  # listed in the sitemap, with nothing the admin could see deciding which one
  # lost. All from a single missed field on the page form, which reported no
  # error anywhere.
  #
  # This validation is what keeps a blank segment from ever reaching
  # `PublicSite::Paths` in the first place; `HasPublicPaths`'s own validation
  # (app/models/concerns/has_public_paths.rb) and the `public_paths (locale,
  # path)` unique index are what additionally catch two *different*, non-blank
  # slugs that would still resolve to the same address.
  #
  # The root is exempt because its slug is `""` by design (see
  # `PublicSite::Paths.page_path`): the homepage contributes no segment and its
  # path is "/".
  #
  # A raw jsonb-hash check, not `validates :slug, presence: true` (which
  # reads the plain Mobility reader, i.e. whichever locale happens to be
  # ambient when this save runs) -- the same ambient-locale trap
  # `title_present_in_any_locale` above already sidesteps, and for the same
  # reason it now matters here too: languages are runtime data (spec §4.1),
  # so the request's ambient locale (I18n's fixed default, `:en`) is no
  # longer guaranteed to be one of the site's enabled languages. A page
  # titled and slugged only in "de" -- with "en" never touched and possibly
  # not even enabled -- would otherwise fail this check for a locale nobody
  # is serving, even though `LocalizedSlug#fill_blank_slugs` already gave it
  # a slug in every locale that *is* enabled.
  validate :slug_present_in_any_locale, unless: -> { parent_id.nil? }

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
  # Runs on every save rather than only when the slug or the parent changed:
  # `slug` is a Mobility jsonb attribute, so `saved_change_to_slug?` reports on
  # the whole translation hash and Mobility offers no per-locale equivalent to
  # narrow it with. The cost of being unconditional is a hierarchy query on a
  # save that touched neither; the cost of guessing wrong is a page silently
  # unreachable at its own URL.
  after_save :sync_public_paths

  private

  # The homepage's slug is "" by design (see `PublicSite::Paths.page_path`).
  def generates_slugs?
    parent_id.present?
  end

  def sync_public_paths
    PublicSite::Paths.sync_subtree(self)
    resync_listed_posts
  end

  # A page's own save can hand a post_list block a new position in the tree
  # without the block itself changing at all -- `sync_subtree` above already
  # rewrote this page's (and its descendants') paths for that, but every post
  # any of *their* post_list blocks list also needs its canonical page
  # re-derived, since tree order -- not just this page's own path -- is what
  # `PublicSite::Paths.canonical_page` ranks candidates by (spec §5.3).
  #
  # Scoped to this subtree's own post_list blocks on an ordinary content save
  # (title, slug, publish state, ...): those are the only blocks whose
  # candidate set could possibly have changed just because *this* page
  # changed. A parent change or a reorder is different -- it can shift this
  # page's rank relative to post_list blocks *outside* its own subtree too
  # (a page moved past a sibling that hosts one), so those resync every type
  # any post_list block anywhere names, via `sync_posts(nil)`.
  def resync_listed_posts
    if saved_change_to_parent_id? || saved_change_to_position?
      PublicSite::Paths.sync_posts(nil)
      return
    end

    types = ContentBlock.post_list.where(page_id: self_and_descendant_ids).map { |block| block.settings["content_type"].presence }
    types.include?(nil) ? PublicSite::Paths.sync_posts(nil) : types.uniq.each { |type| PublicSite::Paths.sync_posts(type) }
  end

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :title_present_in_any_locale`.
  def title_present_in_any_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h.values.all?(&:blank?)
  end

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :slug_present_in_any_locale`.
  def slug_present_in_any_locale
    errors.add(:slug, :blank) if read_attribute(:slug).to_h.values.all?(&:blank?)
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
