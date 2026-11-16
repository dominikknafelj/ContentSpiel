module Admin
  module EditorScreen
    # "Publish now" on a scheduled record (version history spec D9): what goes
    # live, the version that was scheduled or the rows with the changes saved
    # since, asked when there is a choice.
    #
    # ONE STEADY DIALOG for both cases, DRAWN ONCE WITH THE PAGE, as a sibling
    # after the header, for a scheduled record and a viewer who may publish
    # it. Whether changes were saved since the schedule is known only when the
    # dialog opens (a save may land between the page's load and the press), so
    # the body is the server's answer to `POST publishing_changes(part:
    # "publish_now")`, read through the write queue by `admin--editor--publish-dialog`
    # as the Publish changes dialog's overview is: the plain sentence, or the
    # line, the two choices and "What changed since". The card draws the plain
    # case as a confirm dialog; it is the same frame here because only the read
    # tells the two apart, and a frame that changed kind on opening would move
    # under the pointer.
    #
    # THE FORM IS NEVER REPLACED. It stands in the body, empty but for
    # `pending`, and is sent through `admin--saving--queue-hold`, which holds a
    # press made while a save is out (docs/reference/publishing.md, "The header,
    # and why its forms are never replaced"). The answer's two radios belong to
    # it by their `form` attribute: they are read when the press is sent, and
    # are replaced only by the next opening's read. A press made before the
    # answer arrives sends no `with_changes`, which is the scheduled version:
    # what "Publish now" has always published.
    #
    # The confirm's label follows the chosen radio ("Publish the scheduled
    # version" / "Publish with the later changes", "Publish now" with no
    # choice), so the press says what goes live; its words are this
    # component's keys, handed to the script through `data-messages`.
    #
    # `answer` is the same component in its other part: what the POST answers,
    # with no frame and no form.
    class PublishNowDialogComponent < Admin::AdminComponent
      # The confirm's three labels, for the script (`chose`).
      MESSAGES = %w[
        components.editor_screen.publish_now_dialog.confirm
        components.editor_screen.publish_now_dialog.choices.scheduled.title
        components.editor_screen.publish_now_dialog.choices.with_changes.title
      ].freeze

      def self.dialog_id_for(record) = "publish-now-#{PublishChangesDialogComponent.kind_of(record)}-#{record.id}"
      def self.form_id_for(record) = "#{dialog_id_for(record)}-form"

      # The body the dialog is filled with. `changes` is the comparison of the
      # rows with what was scheduled when the rows have changed since, else
      # nil (the plain sentence); `lost` and `moved` are the publish trial's,
      # as the Publish changes dialog's overview shows them.
      def self.answer(record:, changes:, holds:, locale:, lost: [], moved: [], url_options: {})
        new(record: record, locale: locale, url_options: url_options, answer: { changes: changes, holds: holds, lost: lost, moved: moved })
      end

      def initialize(record:, locale:, url_options: {}, answer: nil)
        @record = record
        @locale = locale.to_s
        @url_options = url_options
        @answer = answer
      end

      def answer? = !@answer.nil?

      def choice? = answer? && !@answer[:changes].nil?

      def type = PublishChangesDialogComponent.kind_of(record)
      def dialog_id = self.class.dialog_id_for(record)
      def form_id = self.class.form_id_for(record)

      def title = t(".title", title: ::Locales.read(record, :title, locale: locale))

      def changes_url
        url = helpers.admin_publishing_changes_path(kind: type, id: record.id, **url_options)
        "#{url}#{url.include?("?") ? "&" : "?"}part=publish_now"
      end

      def publish_url = helpers.public_send("publish_admin_#{type}_path", record, **url_options)

      def dialog_data
        { controller: "admin--editor--publish-dialog", admin__editor__publish_dialog_url_value: changes_url,
          action: "admin--ui--dialog:opening@window->admin--editor--publish-dialog#opening",
          messages: messages_data(*MESSAGES) }
      end

      def queue_hold = { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" }

      # The pending copy as this page view knew it; each answer sets it again
      # (`[data-publishing-schedule]`), and the service refuses a press made on
      # older news (`Publishing::ShownSchedule`).
      def pending_id = ::Publishing.pending(record)&.id

      # When the record was to go live: its `published_at`, the one clock of a
      # scheduled record's visibility.
      def scheduled_time = I18n.l(record.published_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

      def overview
        Admin::Ui::ChangesOverviewComponent.new(record: record, changes: @answer[:changes], holds: @answer[:holds], locale: locale,
          lost: @answer[:lost], moved: @answer[:moved], url_options: url_options)
      end

      def choice_tile(value, key, checked:)
        Admin::Ui::ChoiceTileComponent.new(name: "with_changes", value: value, title: t(".choices.#{key}.title"), line: t(".choices.#{key}.line"),
          checked: checked, id: "#{dialog_id}-#{key}", form: form_id)
      end

      def disclosure_class = "admin-disclosure w-fit #{Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)}"

      private

      attr_reader :record, :locale, :url_options
    end
  end
end
