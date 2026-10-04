module Admin
  module EditorScreen
    # The form inside the New page dialog (design pass round 2, handoff §10 /
    # `Studio Modals.dc.html`): Title, Inside (a `<select>` of the pages the
    # viewer may create under, indented by depth), Page type and a live
    # "URL: /about/team" line. It is its own component, not part of the dialog,
    # for two reasons: the no-JS `GET /pages/new` page renders the same form
    # without a dialog around it, and a refused create answers with a Turbo
    # Stream that REPLACES just this form (`#new-page-form`) in the open dialog
    # -- typed values kept, the error summary on top and focused -- so the
    # dialog never closes and the editor behind it never reloads.
    #
    # Inside lists the kept pages a new page may go under: `can?("pages.create",
    # Page.new(parent: page))` per page, its branch grants (`page_ids`) applied
    # to the branch the new page would join (so a branch editor sees their
    # branch, and Home only if allowed), trashed pages never (only kept pages
    # are looked at). It is NOT `AccessControl.scope(..., "pages.create", ...)`:
    # that narrows to the pages whose *parent* is in the branch, i.e. the
    # would-be new pages, not the parents. `preload_branches` gives every page
    # its closure-table branch in one query, so the per-page checks add none.
    # The server still decides: a forged `parent_id` is 404 (unreadable) or a
    # `denied` from `Pages::Save`.
    #
    # The URL line's prefix comes from each option's `data-path` (the parent's
    # stored public path in the editing language, locale prefix included, no
    # trailing slash), the slug part from `admin--new-record`, which slugifies
    # the typed title exactly like `admin--slug-preview`. The server renders a
    # first guess (`parameterize`) so the line is right before any script runs.
    class NewPageFormComponent < Admin::AdminComponent
      FORM_ID = "new-page-form".freeze
      TITLE_ID = "new-page-title".freeze
      INSIDE_ID = "new-page-inside".freeze
      TYPE_ID = "new-page-type".freeze

      Choice = Struct.new(:id, :title, :depth, :path, keyword_init: true) do
        def label = "#{"  " * depth}#{title}"
      end

      # `errors` is an `ActiveModel::Errors`, a hash or an array of sentences
      # (`Admin::ErrorSummaryComponent` takes all three).
      def initialize(url_options: {}, locale: ::Locales.default, parent_id: nil, title: nil, page_type: nil, errors: nil)
        @url_options = url_options
        @locale = locale.to_s
        @requested_parent_id = parent_id.presence&.to_i
        @title = title.to_s
        @page_type = Page.page_types.key?(page_type.to_s) ? page_type.to_s : "standard"
        @errors = errors
      end

      def creatable? = choices.any?

      def render? = creatable?

      def form_id = FORM_ID

      def url = helpers.admin_pages_path(**url_options)

      # Depth-first, siblings in tree order, so the indented list reads like the
      # tree. Ancestors the viewer can't create under are walked but not listed.
      def choices
        @choices ||= begin
          kept = AccessControl.preload_branches(Page.kept.to_a)
          allowed = kept.select { |page| can?("pages.create", Page.new(parent: page)) }.map(&:id).to_set
          children = kept.group_by(&:parent_id).transform_values { |pages| pages.sort_by { |page| [ page.position.to_i, page.id ] } }
          paths = PublicPath.current.where(record_type: "Page", locale: locale).pluck(:record_id, :path).to_h
          prefix = PublicSite::Urls.new.prefix(locale)
          list = []
          walk = lambda do |parent_id, depth|
            Array(children[parent_id]).each do |page|
              if allowed.include?(page.id)
                list << Choice.new(id: page.id, depth: depth, path: path_for(prefix, paths[page.id]),
                  title: ::Locales.read(page, :title, locale: locale).presence || "Untitled")
              end
              walk.call(page.id, depth + 1)
            end
          end
          walk.call(nil, 0)
          list
        end
      end

      # The preset parent when it is one the viewer may create under, else Home
      # (the first, shallowest choice), else whatever is first.
      def selected_choice
        @selected_choice ||= choices.find { |choice| choice.id == requested_parent_id } || choices.first
      end

      def page_type_options = Page.page_types.keys.map { |key| [ key.humanize, key ] }

      attr_reader :title, :page_type, :locale

      def title_value = title

      def initial_url
        "URL: #{selected_choice&.path}/#{title.parameterize}"
      end

      def initial_note
        "Created as a draft at the end of #{selected_choice&.title}. Drag it in the tree to move it."
      end

      def error_summary
        @error_summary ||= normalise(errors)
      end

      def field_ids = { "title" => TITLE_ID, "slug" => TITLE_ID, "parent" => INSIDE_ID, "page_type" => TYPE_ID }

      def title_invalid? = error_summary.is_a?(Hash) && (error_summary.key?("title") || error_summary.key?("slug"))

      private

      attr_reader :url_options, :requested_parent_id, :errors

      def path_for(prefix, path)
        path = path.to_s
        "#{prefix}#{path == "/" ? "" : path}"
      end

      def normalise(errors) = NewRecordErrors.summarise(errors)
    end
  end
end
