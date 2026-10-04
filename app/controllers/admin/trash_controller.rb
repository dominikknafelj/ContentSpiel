module Admin
  # The Trash screen (trash spec §7): everything the viewer could restore,
  # newest first, 50 per page, paged by page number (`Pagination`, design
  # pass spec §4) with the total counted over the same scoped relations the
  # rows are loaded from.
  # Items are loaded only through `AccessControl.scope(..., trashed: true)`
  # (pages and posts, keyed on their *delete* right, so a scoped
  # `pages.delete` narrows the list to its branch) or `Media::Asset.trashed`
  # filtered by the same rule `Trash::ItemPermissions` applies to an image
  # (`media.manage`, or its uploader holding `media.upload`) -- an id the
  # viewer can't act on is "not found", never "forbidden".
  #
  # Pages are listed by branch *root* only (`trash_root_id = id`): the page
  # an editor actually picked, its branch members shown as "+N subpages"
  # under it. A subpage trashed on its own, earlier, is a root of its own
  # and so has its own row, even while the page above it is in the trash
  # too -- restoring it then needs a new parent (`needs_parent?` in
  # `Admin::TrashScreen::RowComponent`), and its Delete permanently works on its
  # own (`Trash::Purge` only refuses a branch *member* whose root is still
  # in the trash).
  #
  # Every write is a `Trash::` service; this controller only turns its
  # `Result` into a redirect with a flash (`forbidden_or` for a permission
  # refusal, the ordinary alert otherwise).
  class TrashController < BaseController
    PER_PAGE = 50
    MODELS = { "page" => Page, "post" => Post, "media" => Media::Asset }.freeze

    # Trashed items of `type` ("page"/"post"/"media") that `actor` may act
    # on, as a relation -- the one place that rule lives, shared by this
    # screen (`visible`, `roots`) and the sidebar's Trash badge
    # (`BaseController#trash_badge_count`), so the badge can never count
    # something the list wouldn't show. Pages and posts go through
    # `AccessControl.scope(..., trashed: true)` on their *delete* right;
    # images are `Trash::ItemPermissions`' rule as a relation:
    # `media.manage` sees every trashed image, an uploader with
    # `media.upload` only their own (both admin-area keys, so holding one
    # anywhere is holding it).
    def self.visible(type, actor)
      case type
      when "page" then AccessControl.scope(actor, "pages.delete", Page.all, trashed: true)
      when "post" then AccessControl.scope(actor, "posts.delete", Post.all, trashed: true)
      when "media" then visible_assets(actor)
      end
    end

    def self.visible_assets(actor)
      scope = Media::Asset.trashed
      return scope if AccessControl.holds?(actor, "media.manage")
      return scope.where(created_by_id: actor.id) if actor.is_a?(User) && AccessControl.holds?(actor, "media.upload")

      scope.none
    end
    private_class_method :visible_assets

    # What the screen lists and counts: `visible`, narrowed for pages to
    # branch roots (`trash_root_id = id`) -- a branch member shows as "+N
    # subpages" under its root, never as a row (or a count) of its own.
    def self.roots(type, actor)
      relation = visible(type, actor)
      type == "page" ? relation.where("pages.trash_root_id = pages.id") : relation
    end

    # The total the sidebar badge shows: one COUNT per type over `roots`.
    def self.badge_count(actor) = MODELS.keys.sum { |type| roots(type, actor).count }

    before_action :require_trash_access
    before_action :set_item, only: %i[restore purge]

    def index
      @type = params[:type].presence_in(MODELS.keys)
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: total_count)
      # A page past the end shows the "back to page 1" notice and no rows:
      # don't load `offset + 50` records per type just to drop them all.
      @items = @pagination.out_of_range? ? [] : listed_items
      @retention_days = Current.site.trash_retention_days
    end

    # `params[:from] == "undo"` is the flash's own Undo link (Task 10, added
    # to its URL by each module's `#destroy`): restoring the one item it
    # named lands the actor back on that item's own CS Studio screen ("as if
    # the delete never happened") rather than the Trash screen they never
    # chose to open. Every other restore -- from the Trash list itself, in
    # place or under a new parent -- still lands back there, with the fuller
    # `restored_notice` (slug changes, images brought along).
    def restore
      service = Trash::Restore.new(@item, parent: chosen_parent)
      result = service.call
      return forbidden_or(result) { redirect_to admin_trash_path(**admin_url_options), alert: result.errors.to_sentence, status: :see_other } unless result.ok?

      if params[:from] == "undo"
        redirect_to item_screen_path, notice: "Restored “#{title_of(@item)}”", status: :see_other
      else
        redirect_to admin_trash_path(**admin_url_options), notice: restored_notice(service), status: :see_other
      end
    end

    def purge
      title = title_of(@item)
      result = Trash::Purge.call(@item)
      return forbidden_or(result) { redirect_to admin_trash_path(**admin_url_options), alert: result.errors.to_sentence, status: :see_other } unless result.ok?

      redirect_to admin_trash_path(**admin_url_options), notice: "Deleted “#{title}” permanently", status: :see_other
    end

    def empty
      service = Trash::Empty.new
      result = service.call
      return forbidden_or(result) { redirect_to admin_trash_path(**admin_url_options), status: :see_other } unless result.ok?

      notice = "Emptied the trash: #{service.purged_count} deleted permanently"
      notice += ", #{service.skipped.size} kept (still in use)" if service.skipped.any?
      redirect_to admin_trash_path(**admin_url_options), notice:, status: :see_other
    end

    private

    # The same keys the sidebar entry shows for (`TRASH_PERMISSIONS`), so
    # the two never disagree; 403 when none is held, like
    # `require_permission`.
    def require_trash_access
      forbidden! unless holds_any?(TRASH_PERMISSIONS)
    end

    # Any trashed record of `:type` the viewer may act on -- a branch
    # member included (the restore form can bring one back under a new
    # parent). A kept record, or an id of another type, is a 404.
    def set_item
      @item = visible(params[:type]).find(params[:id])
    end

    def visible(type) = self.class.visible(type, Current.actor)

    def types = @type ? [ @type ] : MODELS.keys

    # What the rows are loaded from, before any eager loading: the sum of
    # one scoped count per model. Each goes through `visible`
    # (`AccessControl.scope` / the image rule) and, for pages, the
    # branch-root filter -- so the total can never count a row the list
    # wouldn't show.
    def total_count = types.sum { |type| roots(type).count }

    # Merged in Ruby across the three tables: each source contributes at
    # most `offset + PER_PAGE` of its newest rows -- enough that the merged,
    # re-sorted slice below is exactly what one query over a union would
    # return -- and the merge then drops the earlier pages' rows. (The
    # window grows with the page number, as the old offset paging's did;
    # the page is capped at `Pagination::MAX_PAGE` only to keep the integer
    # sane, and a page past the end simply merges to nothing.)
    def listed_items
      window = @pagination.offset + PER_PAGE
      sources = types.map { |type| listed(type).order(trashed_at: :desc, id: :desc).limit(window).to_a }
      sources.flatten.sort_by { |item| [ -item.trashed_at.to_r, -item.id ] }.drop(@pagination.offset).first(PER_PAGE)
    end

    def roots(type) = self.class.roots(type, Current.actor)

    def listed(type)
      relation = roots(type).includes(:trashed_by)
      case type
      when "page" then relation.includes(:parent)
      when "media" then relation.with_variants
      else relation
      end
    end

    # The item's own editor/detail screen (Task 10's Undo): `params[:type]`
    # is already constrained to `page|post|media` by the route, and `@item`
    # is that very record -- `set_item` (through `visible`) already loaded
    # it as this type, so there's no case this falls through to `nil`.
    def item_screen_path
      case params[:type]
      when "page" then admin_page_path(@item, **admin_url_options)
      when "post" then admin_post_path(@item, **admin_url_options)
      when "media" then admin_medium_path(@item, **admin_url_options)
      end
    end

    # A parent picked in the restore form: kept pages only -- whether the
    # actor may put the page there is `Trash::Restore`'s own check.
    def chosen_parent
      Page.kept.find_by(id: params[:parent_id]) if params[:parent_id].present?
    end

    # "Restored “About” as about-2 (the URL was taken) and 1 image". Slug
    # changes come per locale; the usual case -- the same slug taken in
    # every locale that had it -- reads as one new slug, and only slugs
    # that ended up different name their locales.
    def restored_notice(service)
      notice = +"Restored “#{title_of(@item)}”"
      by_slug = service.slug_changes.group_by { |change| change[:to] }
      if by_slug.one?
        notice << " as #{by_slug.keys.first} (the URL was taken)"
      elsif by_slug.any?
        notice << " as " << by_slug.map { |slug, changes| "#{slug} (#{changes.map { |change| change[:locale] }.join(", ")})" }.to_sentence
        notice << " (the URLs were taken)"
      end
      images = service.restored_assets.size
      notice << " and #{helpers.pluralize(images, "image")}" if images.positive?
      notice
    end

    def title_of(item) = item.title.presence || "Untitled"
  end
end
