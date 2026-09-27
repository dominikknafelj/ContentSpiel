module Admin
  # The Pages module (cs-studio spec §4.1/§5.1) and CS Studio's home. `show`,
  # `update` and `destroy` land in Task 4 -- this task is the tree, the
  # module's landing screen, and creating a page from just a title.
  class PagesController < BaseController
    def index
      @page = nil
    end

    # "+" in the tree, or the module's own "Add a page" (spec §5.1) -- both
    # land here with an optional `parent_id`, asking for nothing but a
    # title. A page with no parent given yet (no page selected in the tree)
    # falls back to the homepage in `create` below, not here: leaving
    # `@page.parent_id` nil is what tells the hidden field (and, if the
    # title turns out blank, the re-rendered form) to show no parent chosen
    # rather than silently pre-filling the homepage's id.
    def new
      @page = Page.new(parent_id: params[:parent_id])
    end

    # Every field but the title goes through the same defaults regardless of
    # who's asking (spec §5.1): a draft, under whichever parent the tree (or
    # the empty state's own link) named, or the homepage if none did. The
    # slug fills itself from the title (`LocalizedSlug#fill_blank_slugs`,
    # run inside `Pages::Save` -> `Page#save`).
    def create
      result = Pages::Save.call(Page.new, attributes: { parent: requested_parent, published: false },
        translations: { admin_locale => { title: params.dig(:page, :title) } })

      if result.ok?
        redirect_to admin_page_path(result.record, **admin_url_options), status: :see_other
      else
        @page = result.record
        render :new, status: :unprocessable_entity
      end
    end

    private

    # `find_by`, not `find`: an absent or stale `parent_id` (the empty
    # state's "Add a page" names none at all) is "use the homepage," not a
    # 404 -- only an *invalid* choice should ever be a hard error, and
    # `Pages::Save` has no rule of its own to catch that distinction since a
    # blank `parent:` there just means "make a new root," which `Page`'s own
    # `only_one_root_page` validation already refuses whenever one exists.
    def requested_parent
      Page.find_by(id: params.dig(:page, :parent_id)) || Page.find_by(parent_id: nil)
    end
  end
end
