module Admin
  module NotesScreen
    # The thread view of the notes frame (notes spec §4.2): a Back link to the
    # list, what the thread is on, its messages and the composer with Resolve,
    # fixed at the bottom. It REPLACES the list in `turbo-frame#notes`, on
    # every width.
    #
    # Two parts with ids of their own: `messages` (everything that is READ:
    # the two rows at the top -- Back and "Notify me", then what the thread is
    # on and Pin, the two settings in `[data-note-actions]` -- the state, the
    # quote and the messages) and `reply` (the field that is TYPED in, with
    # Resolve or Reopen in its bottom row beside Send). A live refresh
    # replaces the first and never the second.
    #
    # Every form here is an ordinary Turbo form that names the notes frame;
    # none is an autosave form. `failed` is what a refused or failed write
    # hands back (`Admin::NoteContainer#failed_form`): the form whose `key` it
    # carries shows the reason and, where there is one, the text.
    #
    # A thread with more than three messages shows the first and the last two
    # and folds the rest into "Show N more" (a `<details>`, no script).
    class ThreadComponent < Admin::AdminComponent
      FOLD_ABOVE = 3

      # The classes of the two controls that are not a shared button (handoff
      # "Thread view with Back"): "Notify me" reads as a link, Pin is an icon.
      FOLLOW_CLASS = "cursor-pointer rounded-cs text-[12px] text-dim underline underline-offset-[3px] hover:text-ink focus-visible:outline-2 focus-visible:outline-accent".freeze
      # "Back to page", row 1's way out of the sheet (the handoff's decision
      # 21): the Notify link's manner at 13px/500.
      LEAVE_CLASS = "cursor-pointer items-center rounded-cs text-[13px] font-medium text-dim underline underline-offset-[3px] hover:text-ink focus-visible:outline-2 focus-visible:outline-accent".freeze
      PIN_CLASS = "flex size-7 cursor-pointer items-center justify-center rounded-cs hover:bg-sunken focus-visible:outline-2 focus-visible:outline-accent".freeze

      def initialize(thread:, listing:, viewer:, locale:, view:, type:, failed: nil, asked: {})
        @thread = thread
        @listing = listing
        @viewer = viewer
        @locale = locale.to_s
        @view = view
        @type = type
        @failed = failed
        @asked = asked || {}
      end

      def dom_id = "note-thread-#{thread.id}"

      private

      attr_reader :thread, :listing, :viewer, :locale, :view, :type, :failed, :asked

      def messages = thread.messages.to_a

      def folded = messages.size > FOLD_ABOVE ? messages[1...-2] : []

      def leading = messages.size > FOLD_ABOVE ? messages.first(1) : messages

      def trailing = messages.size > FOLD_ABOVE ? messages.last(2) : []

      # "Show N more" is drawn open when one of the messages in it is the one
      # being acted on: its edit form or its "Delete this note?" was asked
      # for, or its own write was just refused. Closed, the answer to Edit or
      # Delete would be drawn where nobody sees it, and the press would seem
      # to have done nothing. The same goes for the message a reaction was
      # just given to (`shown`): its chip would vanish under the press.
      def fold_open?
        folded.any? { |record| asked.values_at(:edit, :delete, :shown).include?(record.id) || (failed && failed[:key] == "message-#{record.id}") }
      end

      # The first message carries the "written on" chip, as its content.
      def message(record)
        component = Admin::NotesScreen::MessageComponent.new(message: record, thread: thread, listing: listing, viewer: viewer, type: type, view: view,
          failed: failed, asked: asked)
        record == messages.first && written_on ? component.with_content(origin_chip) : component
      end

      def args = helpers.note_args(listing.container)

      def frame_params = { view: (view unless view == "editor"), **helpers.admin_url_options }.compact

      def back_path = helpers.admin_record_notes_path(*args, **frame_params)

      def change_path(change) = helpers.admin_change_record_note_thread_path(*args, thread, change, **frame_params)

      def reply_path = helpers.admin_record_note_messages_path(*args, thread, **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*args)

      # Whether row 1 has "Back to page" (shown in the sheet below 1024px):
      # not where the notes are in no drawer -- an image's, in the media
      # panel.
      def leave? = type.to_s != "media"

      # Pin and unpin are the moderator's (notes spec §3.4); a resolved thread
      # has no pin (a pinned thread is always open).
      def pinnable? = !thread.resolved? && listing.moderator?(viewer)

      def following? = listing.following?(thread, viewer)

      def frame_form = { data: { turbo_frame: "notes" } }

      def action_class(variant = :ghost) = "#{Admin::Ui::ButtonComponent::SMALL_CLASS} #{Admin::Ui::ButtonComponent::VARIANT_CLASSES.fetch(variant)}"

      def key = "thread-#{thread.id}"

      # The empty form Resolve / Reopen submits from inside the composer.
      def state_form_id = "#{dom_id}-state"

      # A failure of one of this thread's own forms, said WHERE THE BUTTON
      # IS that was pressed (`failed[:form]`, the controller's word for it).
      # The reply, and Resolve or Reopen beside its Send: in the composer --
      # a reply of nothing but spaces has no text to tell it by, and in a
      # long thread a sentence at the top is one nobody sees. Pin and
      # Notify, in the two rows at the top: under those rows.
      COMPOSER_FORMS = %w[reply resolve reopen].freeze

      def own_failure = (failed if failed && failed[:key] == key)

      def reply_failure = (own_failure if own_failure && COMPOSER_FORMS.include?(own_failure[:form].to_s))

      def button_failure = (own_failure unless reply_failure)

      # The warn alert, as CS Studio draws one, at the handoff's 13px.
      REFUSAL_CLASS = "rounded-cs border border-warn bg-warn-tint px-3 py-2 text-[13px] text-warn-ink".freeze

      # Whether what was refused is that the note, or what it was on, is no
      # longer there: the one sentence every notes service answers for that
      # (`Notes::Authorization#gone`). Nothing is left to act on then, and
      # the drawer goes back to the list by itself.
      def gone_refusal? = button_failure[:errors] == [ I18n.t("admin.notes.errors.gone.note") ]

      # What the thread is on, as its group's heading in the list says it.
      def subject_heading
        Admin::NotesScreen::SubjectComponent.new(name: listing.heading_of(listing.subject_of(thread)), type: type, level: :h3)
      end

      # "2 messages · started on DE": the line under what the thread is on.
      def summary
        parts = [ t(".messages", count: messages.size) ]
        parts << t(".started_on", language: thread.origin_locale.upcase) if thread.origin_locale.present?
        safe_join(parts, " · ")
      end

      # "Written on German": only when the thread was started on another
      # language tab than the one being read (notes spec §4.2, §4.5).
      def written_on
        origin = thread.origin_locale
        t(".written_on", language: ::Locales.name(origin)) if origin.present? && origin != locale
      end

      # Drawn like the translation chip (`Admin::Ui::TranslationChipComponent`),
      # which itself always says a translation state and so can't be reused.
      def origin_chip
        tag.span(written_on, data: { note_badge: "origin" },
          class: "inline-flex items-center rounded-cs border border-line-strong px-[5px] font-cs-mono text-[10px] uppercase text-dim")
      end

      def resolver = listing.users[thread.resolved_by_id]
    end
  end
end
