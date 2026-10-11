module Admin
  # A SAVE IS A CLAIM (live-editing spec §4.2). The three autosave actions
  # and `Admin::EditingController#claim` ask here before anything is written:
  # the request's tab takes the subject, renews it, or is refused because
  # another tab holds it live. A refusal is a 409 like a stale save's, so the
  # autosave script pauses the form the same way; nothing is written and
  # nothing audited.
  #
  # WHO CLAIMS NOTHING. A request with no tab id (a script, a client without
  # JavaScript, the MCP server) neither claims nor is refused. Someone who
  # may not save the record claims nothing either: the service answers them
  # with its 403, and a person who can only read can never hold a block
  # against the people who can edit it.
  #
  # The check and the save are not one transaction, like the stale check
  # beside it: two saves within one request's length can both pass, and the
  # stale check stays underneath. Every call here is one statement made
  # BEFORE the service, outside its transaction: a refused claim holds the
  # row's lock to the end of the transaction it is in.
  #
  # INSTANT ACTIONS (Publish, Unpublish, Schedule, "Still correct") are not
  # editing: they take no hold, and are refused only while ANOTHER tab holds
  # the subject they change (`held_elsewhere?`). Moving, adding, duplicating
  # and deleting blocks and a section's layout ignore holds altogether
  # (spec D4) and do not ask here.
  module EditingClaims
    extend ActiveSupport::Concern

    private

    # :taken, :renewed, :refused, or nil when nothing was claimed: no tab id,
    # nobody signed in, or the right to save is missing (the service's own
    # 403 answers then).
    def claim_for(subject, record:)
      tab = Current.editing_tab
      return unless tab && Current.user && ::Editing::Rights.missing(Current.actor, record).nil?

      outcome = ::Editing::Reservation.claim(subject:, record:, user: Current.user, tab:)
      ::Editing::Signals.holder(record, subject, "claimed") if outcome == :taken
      outcome
    end

    def refuse_held(subject, status_id:, error_prefix:)
      hold = ::Editing::Reservation.holder_of(subject)
      strip = Admin::EditorScreen::HoldStripComponent.new(subject:, hold:, viewer: Current.user, kind: :lost)
      render status: :conflict, turbo_stream: [
        turbo_stream.replace(status_id, Admin::Ui::SaveStatusComponent.new(id: status_id, state: :held, live: live_record?(subject), holder: hold, viewer: Current.user)),
        turbo_stream.update(Admin::EditorScreen::HoldStripComponent.slot_id(subject), strip),
        turbo_stream.remove("toast-#{error_prefix}")
      ]
    end

    def release_claim(subject, record:)
      tab = Current.editing_tab
      return unless tab && Current.user

      ::Editing::Signals.holder(record, subject, "released") if ::Editing::Reservation.release(subject:, user: Current.user, tab:)
    end

    # The live reservation of `subject` when it is another tab's (a colleague's,
    # or the signed-in person's own other tab), for an instant action. Nil
    # when the request names no tab (it neither claims nor is refused), when
    # nothing holds the subject, and when the holder is this very tab.
    def held_elsewhere?(subject)
      tab = Current.editing_tab
      return unless tab && Current.user

      hold = ::Editing::Reservation.holder_of(subject)
      hold unless hold.nil? || (hold.user_id == Current.user.id && hold.tab == tab)
    end

    # The sentence an instant action's refusal shows (a flash or a toast).
    def held_refusal_text(subject, hold)
      scope = "admin.components.editor_screen.hold_strip.refused"
      return t("#{scope}.own_tab") if hold.user_id == Current.user&.id
      return t("#{scope}.unknown") unless hold.user

      noun = case subject
      when ::ContentBlock then "block"
      when ::Post then "post"
      else "settings"
      end
      t("#{scope}.#{noun}", name: ::PersonName.of(hold.user))
    end

    # Publish / Unpublish / Schedule: back to the editor with the sentence.
    # Nothing is written, audited or signalled. Returns true after redirecting.
    def refuse_instant_redirect(subject, to:)
      hold = held_elsewhere?(subject) or return false

      redirect_to to, status: :see_other, alert: held_refusal_text(subject, hold)
      true
    end
  end
end
