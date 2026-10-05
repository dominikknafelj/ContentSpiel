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

    # The tabs' `?type=` values (plural, as the tabs name themselves) and the
    # model key each one lists. The singular keys the screen used before are
    # still read, so an old bookmark keeps its tab; anything else is "All".
    TABS = { "pages" => "page", "posts" => "post", "images" => "media" }.freeze

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
    # branch roots (`trash_root_id = id`) -- a branch member shows as "Includes
    # N subpages" under its root, never as a row (or a count) of its own.
    #
    # Exactly `Trash.roots`' own condition, so the list, the tabs and the badge
    # are the pages `Trash::Empty` and the retention job work on. A trashed
    # page with NO `trash_root_id` is therefore not listed: no service leaves
    # one (a branch is trashed, restored and purged with its root); it takes a
    # root's row being deleted around them, which nullifies its members' FK.
    # Listing those here, as this once did, showed rows that Empty trash and
    # the sweep would never take -- the opposite of "one code path". Such a
    # page is still reachable by id (`set_item` loads through `visible`), and
    # the orphan state itself is a roadmap row.
    def self.roots(type, actor)
      relation = visible(type, actor)
      type == "page" ? relation.trash_roots : relation
    end

    # One COUNT per type over `roots`: the numbers on the screen's tabs.
    # The sidebar's badge is their sum (`badge_count`), so a tab, the badge
    # and the rows a tab lists are one code path and cannot drift.
    def self.counts(actor) = MODELS.keys.index_with { |type| roots(type, actor).count }

    # The total the sidebar badge shows.
    def self.badge_count(actor) = counts(actor).values.sum

    include BulkResponses

    before_action :require_trash_access
    before_action :set_item, only: %i[restore purge]

    def index
      @type = tab_type(params[:type])
      @tab = TABS.key(@type)
      @counts = self.class.counts(Current.actor)
      # The sidebar's badge is the sum of these same three counts
      # (`BaseController#trash_badge_count`, memoised in this ivar): hand it
      # over rather than let the layout count each type a second time.
      @trash_badge_count = @counts.values.sum
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: total_count)
      # A page past the end shows the "back to page 1" notice and no rows:
      # don't load `offset + 50` records per type just to drop them all.
      @items = @pagination.out_of_range? ? [] : listed_items
      @retention_days = Current.site.trash_retention_days
      @everything = everything_counts if can?("trash.empty")
      @hidden_items = @items.empty? && !@pagination.out_of_range? && hidden_items?
    end

    # `params[:from] == "undo"` is the flash's own Undo link (Task 10, added
    # to its URL by each module's `#destroy`): restoring the one item it
    # named lands the actor back on that item's own CS Studio screen ("as if
    # the delete never happened") rather than the Trash screen they never
    # chose to open. Every other restore -- from the Trash list itself, in
    # place or under a new parent -- still lands back there, with the fuller
    # `restored_notice` (slug changes, images brought along).
    #
    # A `parent_id` that names no page this viewer can read is refused here
    # (`chosen_parent`), before the service is called, with the service's own
    # sentence for a target that doesn't exist.
    def restore
      parent = chosen_parent
      return redirect_to(trash_return_path, alert: Trash::Restore::UNKNOWN_PARENT, status: :see_other) if parent == :unknown

      service = Trash::Restore.new(@item, parent: parent)
      result = service.call
      return forbidden_or(result) { redirect_to trash_return_path, alert: result.errors.to_sentence, status: :see_other } unless result.ok?

      if params[:from] == "undo"
        redirect_to item_screen_path, notice: "Restored “#{title_of(@item)}”", status: :see_other
      else
        redirect_to trash_return_path, notice: restored_notice(service), status: :see_other
      end
    end

    # The Undo of a bulk trash from the posts list (Task 17): `Trash::Restore`
    # once per named post, each with its own permission check and audit event
    # (the service's), nothing else. Posts only -- the one bulk trash there
    # is. Ids are looked up through `visible("post")`, the trashed posts the
    # viewer may act on: an id that is kept, gone, or out of scope is
    # *counted as not found* and changes nothing. The loop is
    # `Posts::BulkRestore`'s: a restore the service refuses (a denial) or that
    # fails (a post whose type is no longer registered, an exception) is
    # reported and never stops the others.
    def restore_many
      return head :unprocessable_entity unless params[:type] == "post" && params[:ids].is_a?(Array)

      begin
        result = Posts::BulkRestore.call(ids: params[:ids].grep(String))
      rescue ArgumentError
        return head :unprocessable_entity
      end

      flash_bulk_result(done: result.restored, refused: result.refused, failed: result.failed, reasons: result.reasons,
        not_found: result.not_found, verb: "Restored", failed_phrase: "restored")
      redirect_to admin_posts_path(**restore_return_params), status: :see_other
    end

    def purge
      title = title_of(@item)
      result = Trash::Purge.call(@item)
      return forbidden_or(result) { redirect_to trash_return_path, alert: result.errors.to_sentence, status: :see_other } unless result.ok?

      redirect_to trash_return_path, notice: "Deleted “#{title}” permanently", status: :see_other
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

    # The `?type=` of a tab (plural) or an older bookmark's model key; nil
    # (All) for anything else.
    def tab_type(value) = TABS[value.to_s] || value.to_s.presence_in(MODELS.keys)

    # Where a restore, a delete or an empty lands: the trash, on the tab the
    # form was submitted from (`tab`, a hidden field of each row's forms;
    # junk means All). The page number isn't kept: after a restore it may be
    # past the end.
    def trash_return_path
      tab = params[:tab].to_s.presence_in(TABS.keys)
      admin_trash_path(**{ type: tab }.compact, **admin_url_options)
    end

    # What the rows are loaded from, before any eager loading: the tab's
    # own count (`@counts`, from `counts` -- the same scoped counts the
    # badge sums), so the total can never count a row the list wouldn't
    # show.
    def total_count = types.sum { |type| @counts.fetch(type) }

    # What "Empty trash…" would really delete, for its dialog's sentence:
    # `Trash::Empty` runs over `Trash.roots` -- EVERYTHING trashed, not what
    # this viewer may list (`trash.empty` is its own, unscoped right) -- so
    # these are not the tabs' counts. Pages are the branch roots plus every
    # page that goes with one (a branch member).
    def everything_counts
      roots = Trash.roots
      pages = roots[:pages].count
      members = Page.trashed.trash_branch_members.count
      { pages:, subpages: members, posts: roots[:posts].count, images: roots[:assets].count }
    end

    # Whether the tab's kind is in the trash at all while this viewer's list
    # of it is empty (`Admin::TrashScreen::ListComponent::HIDDEN_ITEMS`). Known
    # only for a `trash.empty` holder -- `@everything` is computed for nobody
    # else, so no other viewer learns that the trash holds what they can't see.
    def hidden_items?
      return false unless @everything

      kinds = { "page" => :pages, "post" => :posts, "media" => :images }
      types.any? { |type| @everything.fetch(kinds.fetch(type)).positive? }
    end

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
      when "media" then admin_media_path(selected: @item.id, **admin_url_options)
      end
    end

    # A parent picked in the restore form (pages only; a post or an image
    # has none, and the service ignores one). Looked up through the read
    # scope, which is kept pages only: "not found, not forbidden". An id
    # outside the viewer's read scope, the id of a trashed page and an id
    # that names nothing are all `:unknown`, and `restore` answers the three
    # alike -- loaded with a bare `Page.kept.find_by`, a hidden page reached
    # the service and came back as a 403 (so the form told a forged id that
    # exists from one that doesn't), and an id that named nothing was
    # dropped, the restore going ahead in place as if no parent had been
    # chosen. Whether the actor may put the page under a parent they CAN
    # read is `Trash::Restore`'s own check; the picker offers what
    # `AccessControl.creatable_parents` allows, and a right to create under
    # a page is also the right to read it.
    def chosen_parent
      return nil unless params[:type] == "page" && params[:parent_id].present?

      admin_scope(Page.all).find_by(id: params[:parent_id].to_s) || :unknown
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

    # The list the bulk trash came from (`back[...]`, the filters the Undo URL
    # carries), so Undo lands back on it with its filters: the list's own keys,
    # plain strings only.
    def restore_return_params
      back = params[:back].respond_to?(:to_unsafe_h) ? params[:back].to_unsafe_h : {}
      keys = Admin::PostsController::LIST_KEYS.map(&:to_s)
      back.slice(*keys).select { |_, value| value.is_a?(String) }.symbolize_keys.merge(admin_url_options)
    end

    def title_of(item) = item.title.presence || "(untitled)"
  end
end
