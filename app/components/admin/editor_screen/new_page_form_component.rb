module Admin
  module EditorScreen
    # The form inside the New page dialog: Title, Inside (a `<select>` of the pages the
    # viewer may create under, indented by depth), Template and a live
    # "URL: /about/team" line. It is its own component, not part of the dialog,
    # for two reasons: the no-JS `GET /pages/new` page renders the same form
    # without a dialog around it, and a refused create answers with a Turbo
    # Stream that REPLACES just this form (`#new-page-form`) in the open dialog
    # -- typed values kept, the error summary on top and focused -- so the
    # dialog never closes and the editor behind it never reloads.
    #
    # Inside lists the kept pages a new page may go under
    # (`AccessControl.creatable_parents`: `pages.create` checked against the
    # branch the new page would join, so a branch editor sees their branch --
    # its root included -- and Home only if allowed), trashed pages never (only
    # kept pages are looked at). Indentation is relative to the shallowest page
    # listed, so a branch editor's branch root is not indented by its depth in
    # a tree they mostly can't see. The server still decides: a forged
    # `parent_id` is 404 (unreadable) or a `denied` from `Pages::Save`.
    #
    # The form is loaded when the dialog OPENS, into the shell's turbo-frame
    # (`Admin::Ui::NewRecordDialogComponent`, `GET /pages/new` in a frame request), never with
    # the layout: it costs a page load and a permission check per page, and a
    # rendered copy would go stale after every rename. A site with no page at all
    # has nothing to put Inside: the form then omits the field and the page
    # created is the home page (`Pages::Save` decides whether the viewer may).
    #
    # The URL line's prefix comes from each option's `data-path` (the parent's
    # stored public path in the editing language, locale prefix included, no
    # trailing slash), the slug part from `admin--editor--new-record`, which slugifies
    # the typed title exactly like `admin--editor--slug-preview`. The server renders a
    # first guess (`parameterize`) so the line is right before any script runs.
    class NewPageFormComponent < Admin::AdminComponent
      # The dialog's Create button names this form, so the dialog writes its id.
      FORM_ID = Admin::Ui::NewRecordDialogComponent::KINDS.fetch(:page).form_id
      TITLE_ID = "new-page-title".freeze
      INSIDE_ID = "new-page-inside".freeze
      TEMPLATE_ID = "new-page-template".freeze
      # The URL line's and the note's words, shared with the script (`Admin::Ui::NewRecordDialogComponent::MESSAGES`).
      NEW_RECORD = "admin.components.editor_screen.new_record".freeze

      # The refusal a create answers when the chosen parent went meanwhile
      # (trashed or purged after the form was drawn), on the Inside field.
      def self.gone = I18n.t("admin.components.editor_screen.new_page_form.gone")

      Choice = Struct.new(:id, :title, :depth, :path, keyword_init: true) do
        def label = "#{"  " * depth}#{title}"
      end

      # `errors` is an `ActiveModel::Errors`, a hash or an array of sentences
      # (`Admin::Ui::ErrorSummaryComponent` takes all three).
      def initialize(url_options: {}, locale: ::Locales.default, parent_id: nil, title: nil, template: nil, errors: nil)
        @url_options = url_options
        @locale = locale.to_s
        @requested_parent_id = parent_id.presence&.to_i
        @title = title.to_s
        # The value selected: blank for the theme's first (absent means the
        # default, and a new page stores nothing for it), a declared name
        # otherwise; a name the theme does not declare (a forged one, sent
        # back with the refusal) is shown as the first.
        name = ::Theme.current.page_template(template.to_s)
        @template = name == ::Theme.current.page_template(nil) ? "" : name
        @errors = errors
      end

      def creatable? = choices.any? || no_pages?

      def render? = creatable?

      def form_id = FORM_ID

      def url = helpers.admin_pages_path(**url_options)

      # No page exists at all (not even Home): there is nothing to go Inside,
      # and the page created is the home page.
      def no_pages? = !Page.exists?(parent_id: nil)

      # Depth-first, siblings in tree order, so the indented list reads like the
      # tree: by position, a page without one last, then by id, the one rule
      # `TreeOrder` holds for CS Studio's tree and the public branch too
      # (sorting by the position made a number put a page without one first).
      # Ancestors the viewer can't create under are walked but not listed.
      def choices
        @choices ||= begin
          kept = Page.kept.select(:id, :parent_id, :position, :title).to_a
          allowed = AccessControl.creatable_parents(Current.actor, kept).map(&:id).to_set
          children = kept.group_by(&:parent_id).transform_values { |pages| ::TreeOrder.sort(pages) }
          paths = allowed.empty? ? {} : PublicPath.current.where(record_type: Page.polymorphic_name, record_id: allowed.to_a, locale: locale).pluck(:record_id, :path).to_h
          prefix = PublicSite::Urls.new.prefix(locale)
          list = []
          walk = lambda do |parent_id, depth|
            Array(children[parent_id]).each do |page|
              if allowed.include?(page.id)
                list << Choice.new(id: page.id, depth: depth, path: path_for(prefix, paths[page.id]),
                  title: ::Locales.read(page, :title, locale: locale).presence || untitled)
              end
              walk.call(page.id, depth + 1)
            end
          end
          walk.call(nil, 0)
          shallowest = list.map(&:depth).min.to_i
          list.each { |choice| choice.depth -= shallowest }
        end
      end

      def selected_choice
        @selected_choice ||= choices.find { |choice| choice.id == requested_parent_id } || choices.first
      end

      # The theme's page templates, by their labels in the interface's
      # language, the first as the blank value (see `@template`).
      def template_options
        ::Theme.current.choices(:page_templates).each_with_index.map { |entry, index| [ entry.label_for(I18n.locale), index.zero? ? "" : entry.name ] }
      end

      # Asked for when the theme declares two or more; with one, a new page
      # stores no template (absent means the theme's first).
      def template_field? = ::Theme.current.choices(:page_templates).size >= 2

      attr_reader :title, :template, :locale

      def title_value = title

      def initial_url = t("#{NEW_RECORD}.url", path: "#{selected_choice&.path}/#{title.parameterize}")

      def initial_note
        return t(".home_note") unless selected_choice

        t("#{NEW_RECORD}.page_note", title: selected_choice.title)
      end

      def error_summary
        @error_summary ||= normalise(errors)
      end

      def field_ids = { "title" => TITLE_ID, "slug" => TITLE_ID, "parent" => INSIDE_ID, "template" => TEMPLATE_ID }

      def inside_invalid? = error_summary.is_a?(Hash) && error_summary.key?("parent")

      def title_invalid? = error_summary.is_a?(Hash) && (error_summary.key?("title") || error_summary.key?("slug"))

      private

      attr_reader :url_options, :requested_parent_id, :errors

      # `I18n.t`, not the view's `t`: `#new` asks for `choices` before the
      # form is rendered, when a component has no view context yet.
      def untitled = @untitled ||= I18n.t("admin.components.editor_screen.new_page_form.untitled")

      def path_for(prefix, path)
        path = path.to_s
        "#{prefix}#{path == "/" ? "" : path}"
      end

      def normalise(errors) = NewRecordErrors.summarise(errors)
    end
  end
end
