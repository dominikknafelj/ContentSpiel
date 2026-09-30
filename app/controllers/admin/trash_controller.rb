module Admin
  # The Trash screen (trash spec §7): everything the viewer could restore,
  # newest first, 50 per page with the Media module's `limit(N+1)` paging.
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

    before_action :require_trash_access
    before_action :set_item, only: %i[restore purge]

    def index
      @type = params[:type].presence_in(MODELS.keys)
      @offset = offset
      items = listed_items
      @has_next = items.size > PER_PAGE
      @items = items.first(PER_PAGE)
      @retention_days = Current.site.trash_retention_days
    end

    def restore
      service = Trash::Restore.new(@item, parent: chosen_parent)
      result = service.call
      return forbidden_or(result) { redirect_to admin_trash_path(**admin_url_options), alert: result.errors.to_sentence, status: :see_other } unless result.ok?

      redirect_to admin_trash_path(**admin_url_options), notice: restored_notice(service), status: :see_other
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

    def visible(type)
      case type
      when "page" then AccessControl.scope(Current.actor, "pages.delete", Page.all, trashed: true)
      when "post" then AccessControl.scope(Current.actor, "posts.delete", Post.all, trashed: true)
      when "media" then visible_assets
      end
    end

    # `Trash::ItemPermissions`' image rule, as a relation: `media.manage`
    # sees every trashed image, an uploader with `media.upload` only their
    # own. (`media.manage`/`media.upload` are admin-area keys, so holding
    # one anywhere is holding it.)
    def visible_assets
      scope = Media::Asset.trashed
      return scope if can?("media.manage")
      return scope.where(created_by_id: Current.user.id) if Current.user && can?("media.upload")

      scope.none
    end

    # Merged in Ruby across the three tables: each source contributes at
    # most `offset + PER_PAGE + 1` of its newest rows -- enough that the
    # merged, re-sorted slice below is exactly what one query over a union
    # would return -- and the one extra row is how `@has_next` is known
    # without a `COUNT(*)`.
    def listed_items
      window = @offset + PER_PAGE + 1
      sources = (@type ? [ @type ] : MODELS.keys).map { |type| listed(type).order(trashed_at: :desc, id: :desc).limit(window).to_a }
      sources.flatten.sort_by { |item| [ -item.trashed_at.to_r, -item.id ] }.drop(@offset).first(PER_PAGE + 1)
    end

    def listed(type)
      relation = visible(type).includes(:trashed_by)
      case type
      when "page" then relation.where("pages.trash_root_id = pages.id").includes(:parent)
      when "media" then relation.with_variants
      else relation
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

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end
  end
end
