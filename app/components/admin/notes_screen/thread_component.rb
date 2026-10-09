module Admin
  module NotesScreen
    # The thread view of the notes frame (notes spec §4.2): a Back link to the
    # list, what the thread is on, its messages and -- from Task 6 -- the
    # composer with Resolve, fixed at the bottom. It REPLACES the list in
    # `turbo-frame#notes`, on every width.
    #
    # Two parts with ids of their own: `messages` (everything that is READ:
    # state, quote, messages, and from Task 6 the thread's buttons) and
    # `reply` (the field that is TYPED in). A live refresh replaces the first
    # and never the second.
    #
    # A thread with more than three messages shows the first and the last two
    # and folds the rest into "Show N more" (a `<details>`, no script).
    class ThreadComponent < Admin::AdminComponent
      FOLD_ABOVE = 3

      def initialize(thread:, listing:, viewer:, locale:, view:, type:, failed: nil)
        @thread = thread
        @listing = listing
        @viewer = viewer
        @locale = locale.to_s
        @view = view
        @type = type
        @failed = failed
      end

      def dom_id = "note-thread-#{thread.id}"

      private

      attr_reader :thread, :listing, :viewer, :locale, :view, :type, :failed

      def messages = thread.messages.to_a

      def folded = messages.size > FOLD_ABOVE ? messages[1...-2] : []

      def leading = messages.size > FOLD_ABOVE ? messages.first(1) : messages

      def trailing = messages.size > FOLD_ABOVE ? messages.last(2) : []

      # The first message carries the "written on" chip, as its content.
      def message(record)
        component = Admin::NotesScreen::MessageComponent.new(message: record, thread: thread, listing: listing, viewer: viewer, type: type, view: view, failed: failed)
        record == messages.first && written_on ? component.with_content(origin_chip) : component
      end

      def args = helpers.note_args(listing.container)

      def frame_params = { view: (view unless view == "editor"), **helpers.admin_url_options }.compact

      def back_path = helpers.admin_record_notes_path(*args, **frame_params)

      def subject_name = helpers.note_subject_name(listing.subject_of(thread), listing.container, type)

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

      # Drawn like the translation chip (`Admin::TranslationChipComponent`),
      # which itself always says a translation state and so can't be reused.
      def origin_chip
        tag.span(written_on, data: { note_badge: "origin" },
          class: "inline-flex items-center rounded-cs border border-line-strong px-[5px] font-cs-mono text-[10px] uppercase text-dim")
      end

      def resolver = listing.users[thread.resolved_by_id]
    end
  end
end
