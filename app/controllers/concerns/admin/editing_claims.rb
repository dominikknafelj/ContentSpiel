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
  # A controller that includes this must also include
  # `Admin::AutosaveResponses` where it calls `refuse_held` (it uses
  # `live_record?` and Turbo's `turbo_stream`); the instant actions
  # (`held_elsewhere?`, `refuse_instant_redirect`) need neither.
  #
  # THE ORDER IN AN AUTOSAVE ACTION is in two calls, and nowhere else:
  # `claim_before_save` (claim, refusal, the stale check with its give-back)
  # and then `saving_under` around the service. An action reads its parameters
  # between the two and uses them after the save, which is why they are two
  # methods and not one that takes the save as a block.
  #
  # A CLAIM THIS REQUEST TOOK is given back when the save does not happen: a
  # stale refusal, a denied service, an exception (`saving_under`). A 422
  # keeps it (the person is still typing). A renewal is never given back.
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
  # and deleting blocks ignore holds altogether (spec D4) and do not ask here.
  # A section's layout is NOT among them, whatever D4 says: layout, background
  # and width are the section block's own settings form, saved by
  # `ContentBlocksController#update`, which claims the section like any block.
  # The fold a narrower layout causes writes the other blocks with
  # `update_columns`, so it moves no held block's base.
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

    # What an autosave action does before it reads its form, in the one order
    # that is right (final review M5: these lines stood in three actions):
    #   1. the claim: the tab takes the subject, renews it, or is refused;
    #   2. the refusal, a 409, when another tab holds it, whatever the base is;
    #   3. the stale check, which gives back a claim this very request took.
    # Answers the claim for `saving_under`. When it has rendered a refusal the
    # action is over: `return if performed?`.
    def claim_before_save(subject, record:, status_id:, error_prefix:, reload_url:)
      claim = claim_for(subject, record:)
      if claim == :refused
        refuse_held(subject, status_id:, error_prefix:)
      elsif refuse_stale_autosave(subject, status_id:, error_prefix:, reload_url:)
        release_claim(subject, record:) if claim == :taken
      end
      claim
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

    # Runs the save, and gives back a claim this request `:taken` when the
    # service answers denied or raises. Returns the service's result.
    def saving_under(claim, subject, record:)
      result = yield
      release_claim(subject, record:) if claim == :taken && result.denied?
      result
    rescue StandardError
      release_claim(subject, record:) if claim == :taken
      raise
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
    #
    # It is asked BEFORE the service's own `authorize!`, so a forged Publish by
    # someone in the read scope but without the right gets "is editing" and no
    # `access.denied` event while a hold exists. Accepted: they are in the read
    # scope and see the very strip that names the holder, so nothing new is
    # disclosed, and asking the right here would need a second copy of each
    # action's rule (a publish-only person is refused too).
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

    # A discard writes every part of a page (its settings and each of its
    # blocks) or the whole post, so it is refused while ANOTHER tab holds any
    # of them (drafts spec §4.3; live-editing's rule: a write to a held
    # subject from another tab is refused). It would overwrite text someone
    # is typing. Nothing is written, audited or signalled. A request with no
    # tab id is not refused, as everywhere. It reads the holds
    # (`Editing::Holds`) and runs no statement of a reservation's.
    def refuse_discard_under_hold(record, to:)
      tab = Current.editing_tab
      return false unless tab && Current.user

      holds = ::Editing::Holds.on(record, viewer: Current.user, tab: tab)
      subjects = [ record, *(record.is_a?(::Page) ? ::ContentBlock.where(owner: record).to_a : []) ]
      subject = subjects.find { |candidate| holds.other(candidate) } or return false

      redirect_to to, status: :see_other, alert: held_refusal_text(subject, holds.other(subject))
      true
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
