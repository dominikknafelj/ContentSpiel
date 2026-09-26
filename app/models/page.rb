class Page < ApplicationRecord
  extend Mobility
  include SlugGeneration
  include Publishable

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

  validates :title, presence: true

  # A page's path is its ancestors' slugs plus its own, and `build_path` drops
  # blank segments -- so a non-root page without a slug contributes nothing and
  # lands on its parent's path exactly. A slugless child of the root gets
  # `cached_paths` of {"en" => "/", ...}: the homepage's own paths.
  #
  # Two pages then answer to one URL, and `find_by_full_path` can only return
  # one of them: the other is unreachable at any address at all, while still
  # being listed in the sitemap. Which one loses is decided by nothing the
  # admin can see -- it is whichever has the higher `id`, so blanking the slug
  # of a page that happens to predate its new neighbour takes that neighbour's
  # URL away from it. All of this from a single missed field on the page form,
  # which reported no error anywhere.
  #
  # The root is exempt because its slug is `""` by design (see
  # `path_segment_pages`, which drops it): the homepage contributes no segment
  # and its path is "/".
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
  validate :slug_is_unused_among_siblings_in_every_locale

  # Prepended so it runs ahead of the callbacks `has_closure_tree` installed:
  # closure_tree's own `_ct_before_destroy` tears down this page's hierarchy
  # rows before any later callback gets a say. Throwing :abort from the front
  # of the chain means nothing is touched at all.
  before_destroy :ensure_no_children, prepend: true

  # Declared *after* `has_closure_tree`, so it runs after closure_tree's own
  # `after_save` -- which is what creates and rebuilds the hierarchy rows this
  # callback reads back to assemble the path.
  #
  # Runs on every save rather than only when the slug or the parent changed:
  # `slug` is a Mobility jsonb attribute, so `saved_change_to_slug?` reports on
  # the whole translation hash and Mobility offers no per-locale equivalent to
  # narrow it with. The cost of being unconditional is a hierarchy query on a
  # save that touched neither; the cost of guessing wrong is a page silently
  # unreachable at its own URL.
  after_save :recompute_cached_paths

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

  # This page's URL path in `locale`, e.g. "/about/team". Served from the
  # `cached_paths` column that `recompute_cached_paths` maintains; the block is
  # the fallback for a row written before that column existed.
  def full_path(locale)
    cached_paths.fetch(locale.to_s) { compute_full_path(locale) }
  end

  # The lookup the catch-all route performs on every request: one indexed
  # equality test against this locale's key in `cached_paths`, rather than
  # rebuilding every page's ancestor chain in Ruby to find the one that matches.
  #
  # Scoped to published pages rather than leaving that to the caller: this is
  # the public site's entry point into the tree, and a draft page acquires its
  # path the moment it is saved -- so an unfiltered lookup publishes every
  # work-in-progress at a guessable URL.
  #
  # Ordered by `id` before taking the first row: two published pages mapped to
  # the same path have to resolve to one of them, and to the same one every
  # time. Oldest-first means the incumbent keeps the URL rather than a page
  # created later taking it over.
  #
  # Explicit rather than implied: `.first` on an unordered relation already
  # appends `ORDER BY id ASC` itself, so this emits the same SQL today. It is
  # written out because the guarantee above is one this lookup makes on
  # purpose, not one to inherit from an ActiveRecord internal -- `.take`, or a
  # later `.order` added for some other reason, would quietly withdraw it.
  # (The slug presence validation above is what actually keeps two pages off
  # one path; this is the tiebreak for a collision arriving some other way.)
  #
  # Preview (signed-in editors) passes `include_unpublished: true`.
  def self.find_by_full_path(locale, path, include_unpublished: false)
    scope = include_unpublished ? all : published
    scope.where("cached_paths ->> ? = ?", locale.to_s, path).order(:id).first
  end

  protected

  # Writes `paths` onto this page, then hands each child the paths it now sits
  # under. Recursive because a slug change shifts the whole subtree below it,
  # not just the direct children.
  #
  # `update_columns` writes straight to the database on purpose: a plain
  # `update` would re-enter the `after_save` above on every descendant, so an
  # n-level subtree would recompute itself n times over, and it would re-run
  # the sibling slug validation on pages nobody edited.
  def write_cached_paths(paths)
    update_columns(cached_paths: paths) unless cached_paths == paths

    # Queried rather than read off the `children` association: an association
    # loaded earlier in the request would hand back child objects still
    # carrying their pre-update slugs.
    self.class.where(parent_id: id).find_each do |child|
      child.write_cached_paths(child.paths_under(paths))
    end
  end

  # A descendant's path is its parent's path plus its own segment, which is why
  # the cascade can hand paths downwards instead of re-walking the hierarchy
  # table once per descendant.
  def paths_under(parent_paths)
    per_locale do |locale|
      parent_path = parent_paths.fetch(locale.to_s, "/")
      segment = slug_in(locale)
      next parent_path if segment.blank?

      parent_path == "/" ? "/#{segment}" : "#{parent_path}/#{segment}"
    end
  end

  # The slug as a visitor in `locale` sees it -- deliberately through
  # Mobility's fallbacks (spec section 6), so a page with no German slug still
  # contributes its English one and the German path is a usable URL rather than
  # one with a hole where a segment should be. This is the opposite of what the
  # slug uniqueness validation below wants, which is why that one reaches for
  # the literal per-locale accessor instead.
  def slug_in(locale)
    Mobility.with_locale(locale) { slug }
  end

  private

  # The homepage's slug is "" by design (see `path_segment_pages`).
  def generates_slugs?
    parent_id.present?
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

  def recompute_cached_paths
    pages = path_segment_pages
    write_cached_paths(per_locale { |locale| build_path(pages, locale) })
  end

  def compute_full_path(locale)
    build_path(path_segment_pages, locale)
  end

  # The pages whose slugs make up this page's path, root-to-leaf.
  #
  # `self_and_ancestors` is ordered by `generations ASC` and `self` sits at
  # generation 0, so closure_tree hands the chain back *leaf-first* -- it has
  # to be reversed to be walked root-to-leaf. (closure_tree reverses it the
  # same way in its own `ancestry_path`.) `reload` because a chain loaded
  # before this save would still be holding the pre-save slugs.
  #
  # The root is then dropped: it is the homepage and contributes no segment of
  # its own, so its path is "/" and a child of the root is "/about" rather than
  # "//about".
  def path_segment_pages
    self_and_ancestors.reload.reverse.drop(1)
  end

  # Blank segments are dropped rather than joined: only the root is meant to be
  # slugless, and a page that somehow isn't resolves to its parent's path --
  # a content mistake, not a malformed URL like "/about//team".
  def build_path(pages, locale)
    "/" + pages.map { |page| page.slug_in(locale) }.compact_blank.join("/")
  end

  # Every configured locale, not just `Mobility.locale`: the admin edits one
  # locale per request, but the site serves all of them off the same row, so
  # all of them have to be recomputed together.
  def per_locale
    Mobility.available_locales.to_h { |locale| [ locale.to_s, yield(locale) ] }
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

  # `validates :slug, uniqueness:` would emit `WHERE pages.slug = 'about'`,
  # comparing a jsonb column to a string -- which Postgres rejects outright.
  # Mobility's `.i18n` scope rewrites the condition into a lookup of one
  # locale's key inside the column, so two siblings may share a slug as long as
  # they don't share it *in the same locale*.
  #
  # Every locale is checked, not just `Mobility.locale`: the admin form writes
  # all of them in a single request that runs under one ambient locale, so
  # checking only that one lets the rest through to the per-locale unique
  # indexes, where the collision surfaces as a raw Postgres error instead of a
  # form error.
  def slug_is_unused_among_siblings_in_every_locale
    Mobility.available_locales.each do |locale|
      accessor = Mobility.normalize_locale_accessor(:slug, locale)

      # The literal value for this locale. The plain `slug` reader falls back
      # to English, which would ask whether the *English* slug is taken as,
      # say, a German one -- and reject a page over a German slug it does not
      # have.
      value = public_send(accessor)
      next if value.blank?

      # `.i18n` reads the locale off `Mobility.locale` when `where` runs rather
      # than from an argument, so the query is built inside the locale it asks
      # about.
      taken = Mobility.with_locale(locale) do
        scope = Page.i18n.where(slug: value).where(parent_id: parent_id)
        scope = scope.where.not(id: id) if persisted?
        scope.exists?
      end

      # Reported against `slug_de` rather than `slug`, so the admin form marks
      # the offending locale's tab instead of an ambient field nobody edits.
      errors.add(accessor, :taken) if taken
    end
  end

  # Deleting a branch has to be deliberate: the admin removes the leaves first.
  def ensure_no_children
    return if children.empty?

    errors.add(:base, "cannot delete a page that still has children")
    throw :abort
  end
end
