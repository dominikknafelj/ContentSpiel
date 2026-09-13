class Page < ApplicationRecord
  extend Mobility

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
  # through the current Mobility.locale.
  translates :title, :slug, :subtitle, :meta_title, :meta_description

  # A page's body is an ordered list of blocks; the renderer walks them in
  # `position` order and dispatches on each one's `block_type`.
  has_many :content_blocks, -> { order(:position) }, dependent: :destroy

  has_one_attached :hero_image

  enum :page_type, { standard: 0, landing: 1 }

  validates :title, presence: true
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

  # This page's URL path in `locale`, e.g. "/about/team". Served from the
  # `cached_paths` column that `recompute_cached_paths` maintains; the block is
  # the fallback for a row written before that column existed.
  def full_path(locale)
    cached_paths.fetch(locale.to_s) { compute_full_path(locale) }
  end

  # The lookup the catch-all route performs on every request: one indexed
  # equality test against this locale's key in `cached_paths`, rather than
  # rebuilding every page's ancestor chain in Ruby to find the one that matches.
  def self.find_by_full_path(locale, path)
    where("cached_paths ->> ? = ?", locale.to_s, path).first
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
