module Admin
  module Ui
    # The autosave status line every form-with-autosave renders one of (spec
    # §6.1) -- a Turbo Stream replaces this element wholesale by its `id` as a
    # save moves through its states, so the text for each state has to be
    # exactly the wording global constraints pins down (a save controller in a
    # later task assembles the state from the fetch response; this component
    # only ever turns a state into the one sentence it's allowed to show).
    # `idle` -- nothing has changed yet, or the record just loaded -- renders
    # an empty element rather than an empty string with visible chrome around
    # it, so the header note it sits in doesn't visibly flash on load.
    #
    # That empty element still keeps one line's height (`min-h-[1lh]`), so
    # the first save doesn't push everything below it down a line. It used
    # to collapse to nothing, and a first save started by a click's own
    # mousedown (the `focusout` that blurring a field sends straight to
    # `admin--saving--autosave#saveNow`) moved the page between that mousedown and
    # its mouseup: the mouseup landed beside the button, the browser fired
    # no `click`, and the related-posts picker silently dropped the pick.
    class SaveStatusComponent < AdminComponent
      # `signed_out` (final-fixes round, finding 4) is never rendered by any
      # server response -- `autosave_controller.js` sets this text itself, the
      # moment it notices a save's own response redirected (an expired
      # session), rather than a server ever answering a Turbo Stream that
      # replaces this element with it. It's a state here anyway, not a bare
      # string duplicated in the JS, so its wording stays governed by this
      # one class the same way every other state's already is -- and so a
      # Lookbook preview or a future server-side use of it has somewhere to
      # read the exact text from.
      # `:forbidden` is a save a service refused for want of permission
      # (access-control design spec §3.4) -- an editor that's view only never
      # sends one, so it only shows for a stale tab whose rights changed.
      STATES = %i[idle saving saved error stale held saved_over offline retrying signed_out forbidden].freeze

      #
      # Wording (design pass round 2, handoff §4.1): the saved/saving/offline
      # lines are mono capitals ("SAVED 10:42"). A save of a published or
      # scheduled record is NOT a publication (drafts spec §3): its line reads
      # "SAVED · NOT PUBLISHED 10:42", in the neutral colour and without the
      # dot the "SAVED TO SITE" line had, which said "this is on the site" in
      # the ok colour and is no longer true. `live:` is that question, and
      # keeps its name: a page or post with a `published_at`. The
      # capitals are literal text, not a CSS `uppercase`, so what a test or a
      # screen reader reads is exactly what is shown. `live:` also rides on the
      # element (`data-live`) so `autosave_controller.js`, which writes the
      # "saving" line itself, picks the same wording. Every string here that
      # the controller also writes is the same key (`messages_data` hands
      # them to it from <body>), so the two cannot drift.
      # `:held` is a save refused because ANOTHER tab holds the subject
      # (live-editing spec §4.2, handoff 25): "● NOT SAVED · DANA WEISS IS
      # EDITING", or for the person's own other tab "● NOT SAVED · OPEN IN YOUR
      # OTHER TAB". `holder:` is the reservation (a user and a tab), nil when
      # it lapsed between the refusal and this answer; `viewer:` says whose
      # status line it is, so their own other tab can be told from a colleague.
      # The capitals are literal text, like every other state's.
      def initialize(id:, state: :idle, at: nil, count: 0, live: false, holder: nil, viewer: nil)
        raise ArgumentError, "unknown save status state #{state.inspect}" unless STATES.include?(state)

        @id = id
        @state = state
        @at = at
        @count = count
        @live = live
        @holder = holder
        @viewer = viewer
      end

      def text
        case state
        when :idle then ""
        when :saving then t(live ? ".saving_live" : ".saving")
        when :saved then saved_text
        when :error then t(".error", count: count)
        when :forbidden then t(".forbidden")
        when :retrying then t(".retrying")
        # The Retry button is rendered after this text (see the template).
        when :offline then t(".offline")
        # "Not saved": the three record editors refuse a stale save
        # (`Admin::AutosaveResponses#refuse_stale_autosave`).
        when :stale then t(".stale")
        when :held then held_text
        # The opposite meaning, for the forms that still save on a stale base
        # (Settings, media detail, tag rows): the save WENT THROUGH and
        # overwrote, so it must never read like the refusal above.
        when :saved_over then t(".saved_over")
        when :signed_out then t(".signed_out")
        end
      end

      # Only an `offline` line offers Retry (the other failures either retry by
      # themselves or need the fields fixed first).
      def retry_button? = state == :offline

      # A saved line is neutral, whatever the record: nothing went to the
      # site (see the class comment). The refusals keep the warn colour.
      def css_class
        colour = %i[stale held saved_over].include?(state) ? "text-warn-ink" : "text-meta"
        "min-h-[1lh] font-cs-mono text-label tracking-mono #{colour}"
      end

      private

      attr_reader :id, :state, :at, :count, :live, :holder, :viewer

      # Whose it is, in capitals: a name in `PersonName.of` is mixed case, and
      # the line is a mono-capitals line (`upcase` follows Unicode).
      def held_text
        return t(".held_unknown") unless holder&.user
        return t(".held_own_tab") if viewer && holder.user_id == viewer.id

        t(".held", name: ::PersonName.of(holder.user).upcase)
      end

      # "SAVED 14:05", or just "SAVED" for a save with no time (a stream that
      # carries none); a published or scheduled record's own wording says it
      # is not published by that.
      def saved_text
        return t(live ? ".saved_live" : ".saved") unless at

        t(live ? ".saved_live_at" : ".saved_at", time: I18n.l(at, format: :"admin.time"))
      end
    end
  end
end
