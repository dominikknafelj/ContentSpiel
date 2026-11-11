module Admin
  module Ui
    # The New page and New post dialogs (`new-page-dialog`, `new-post-dialog`,
    # 560 wide), one per kind, each rendered ONCE in the layout outside
    # `#content` (forms can't nest). Only the SHELL is rendered there: a
    # loading line, an empty `<turbo-frame>` and a disabled Create button. The
    # form itself is loaded when the dialog opens (`admin--editor--new-record`
    # sets the frame's `src` to `GET /pages/new` or `GET /posts/new`, with the
    # trigger's preset as query params), because building it costs a page load
    # and a permission check per page, or a listing-page lookup per content
    # type -- not something every CS Studio request should pay -- and a copy
    # rendered with the page would go stale after a rename. The shell needs no
    # query: it is rendered when the viewer holds the kind's create right
    # anywhere (`can?` without a record). A trigger without the dialog on the
    # page falls through to its `href`, the standalone no-JS page.
    #
    # Opened with `data: dialog_trigger("new-page-dialog")` merged with
    # `"new-page-parent-id-param": id` and `"new-page-title-param": text`, or
    # `dialog_trigger("new-post-dialog")` with `"new-post-type-param": name`
    # and `"new-post-title-param": text` (read from the trigger's own
    # attributes on the `admin--ui--dialog:opening` event).
    #
    # The two kinds share one markup and differ only in what `KINDS` holds and
    # in their title and Create words. `KINDS` is the one place each kind's
    # ids are written: the form components (`Admin::EditorScreen::
    # NewPageFormComponent`, `NewPostFormComponent`) take their `FORM_ID` from
    # it, because the Create button in this dialog's footer names the form
    # with `form=`, and the controllers answer a frame request by its
    # `frame_id`.
    class NewRecordDialogComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The shared dialog (a native modal named by its title, Escape closes it); its loading line, its load failure as an alert with Try again, and its submit failure as an alert; Cancel and Create are buttons, Create disabled until the form has loaded, and the focus goes to the form's Title, or to its error summary after a refusal.",
        motion: :reduced,
        content_edges: %i[short long],
        widths: :fixed_width,
        interface: %i[kind url_options],
        limits: [
          "It is drawn once per kind, by the admin layout, and only for someone who holds the kind's create right somewhere; the standalone no-JS page skips it.",
          "It draws a shell only: the form is the editor screen's NewPageFormComponent or NewPostFormComponent, loaded into its frame each time it opens, and the script's three sentences are the editor screen's new_record keys, which the forms draw first.",
          "It opens only through admin--ui--dialog, by its id."
        ],
        states: %i[page post],
        script_states: {
          open: [ "test/system/admin/new_record_test.rb", "New post: type a title, choose a type, Create opens that post's editor" ]
        },
        keys: %w[page.title page.create post.title post.create loading load_failed submit_failed retry cancel],
        slots: [],
        controller: "admin--editor--new-record",
        keyboard: [ "test/system/admin/new_record_test.rb", "the New page dialog by the keyboard: Enter on + New page opens it on Title, Tab reaches Create and Enter creates" ]
      )

      # Each kind's dialog and frame ids, its form's id, the right that draws
      # it and the route of the form it loads.
      Kind = Data.define(:name, :id, :frame_id, :form_id, :permission, :path)

      KINDS = {
        page: Kind.new(name: :page, id: "new-page-dialog", frame_id: "new-page-form-frame", form_id: "new-page-form", permission: "pages.create", path: :new_admin_page_path),
        post: Kind.new(name: :post, id: "new-post-dialog", frame_id: "new-post-form-frame", form_id: "new-post-form", permission: "posts.create", path: :new_admin_post_path)
      }.freeze

      # The sentences `admin--editor--new-record` writes as the person types:
      # the URL line, a type no page lists, and the New page note that names
      # the chosen parent. Both kinds hand the same list to the script, so it
      # finds the same keys whichever dialog it runs in. They are the editor
      # screen's keys because the forms draw the first URL line and note from
      # them, so the dialog never changes wording on the first keystroke.
      MESSAGES = %w[
        components.editor_screen.new_record.url
        components.editor_screen.new_record.not_listed
        components.editor_screen.new_record.page_note
      ].freeze

      def initialize(kind:, url_options: {})
        @kind = KINDS.fetch(kind.to_sym) { raise ArgumentError, "unknown kind #{kind.inspect}: one of #{KINDS.keys.join(', ')}" }
        @url_options = url_options
      end

      def render? = can?(kind.permission)

      def form_url = helpers.public_send(kind.path, **url_options)

      def words(key) = t(".#{kind.name}.#{key}")

      private

      attr_reader :kind, :url_options
    end
  end
end
