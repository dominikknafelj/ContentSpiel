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
  validates :slug, presence: true, unless: -> { parent_id.nil? }

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

  # Reordering a branch is done by typing a new `position` (page-tree design
  # spec section 5 waives drag-and-drop, so that number *is* the reordering
  # UI), and the number has to mean "put me at this rank among my siblings".
  #
  # closure_tree does renumber siblings after a position change, but only from
  # the number that was written: two siblings holding the same number is a tie
  # Postgres breaks however it likes, so typing the number of the page you want
  # to get ahead of usually leaves the order exactly as it was. Only a number
  # below every sibling's, or above all of them, moved the page at all.
  #
  # So the rank is applied here instead: the requested number is captured
  # before closure_tree renumbers over it, and the siblings are then written
  # out in the order it asks for. `update_columns` keeps that from re-entering
  # this chain on every sibling, and leaves the dense 0..n-1 numbering
  # closure_tree expects.
  before_save :remember_requested_position
  after_save :place_among_siblings

  # Temporary bridge for PagesController until PublicSite::Resolver (Task 6).
  #
  # Scoped to published pages rather than leaving that to the caller: this is
  # the public site's entry point into the tree, and a draft page acquires its
  # path the moment it is saved -- so an unfiltered lookup publishes every
  # work-in-progress at a guessable URL.
  #
  # Preview (signed-in editors) passes `include_unpublished: true`.
  def self.find_by_public_path(locale, path, include_unpublished: false)
    scope = include_unpublished ? all : published
    scope.where(id: PublicPath.current.where(record_type: "Page", locale: locale.to_s, path: path).select(:record_id)).first
  end

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

  # closure_tree's own `after_save` reloads this record as part of renumbering,
  # which is what takes the requested number back out of reach of the callback
  # that has to act on it.
  def remember_requested_position
    @requested_position = position if will_save_change_to_position?
  end

  def place_among_siblings
    requested = @requested_position
    @requested_position = nil
    return if requested.nil?

    # `self` rather than the row for this page, so the in-memory record ends up
    # holding the position it was actually given.
    others = self.class.where(parent_id: parent_id).where.not(id: id).order(:position, :id).to_a
    ordered = others.insert(requested.clamp(0, others.size), self)

    ordered.each_with_index do |page, index|
      page.update_columns(position: index) unless page.position == index
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
