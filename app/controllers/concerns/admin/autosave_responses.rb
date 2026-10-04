module Admin
  # The Turbo Stream response shape every autosaving form shares (cs-studio
  # spec §6.1/§5.1): the page settings form, a block card and the post form
  # all answer their own PATCH endpoint through this one shared shape,
  # rather than each re-deriving "what does a save response look like" on
  # its own.
  #
  # `record:` and `result:` are kept separate deliberately, not just
  # `result.record` read twice: `result.errors` (an array of full messages,
  # `ApplicationService::Result`'s own shape) is what the status line's
  # error *count* comes from, while `record.errors` (the live
  # `ActiveModel::Errors` object) is what the *per-field* slots read --
  # `full_messages_for(attribute)` there is what lets one field's slot show
  # only the messages that belong to it, keyed however the caller's own
  # validations actually reported them (see `fields:` below).
  module AutosaveResponses
    extend ActiveSupport::Concern

    # `fields:` maps each UI field name (used to compute its error-slot id,
    # via `Admin::FieldComponent.error_id(error_prefix, field)`) to the
    # actual `ActiveModel::Errors` attribute name(s) to read for it -- a
    # bare `:subtitle` is also its own error key, but a translated field
    # validated per-locale (`LocalizedSlug`'s `slug_de`/`slug_en`) has no
    # single matching key, so the caller resolves *which* locale-suffixed
    # accessor is actually in view (`Mobility.normalize_locale_accessor`)
    # and hands that over instead. Every named field is always replaced,
    # even with zero messages -- that's what clears a slot's *previous*
    # error once the value that caused it is fixed, since each autosave
    # PATCH resends the whole form and this always reflects the record's
    # complete, current validity rather than only what changed.
    #
    # Which forms refuse a stale save and which do not. The page settings
    # form, a block card and the post form refuse (`#refuse_stale_autosave`):
    # they have the `#editor-notice` area for the explanation bar and a
    # Reload. Settings, the media detail panel and the tag rows still save on
    # a stale base and pass `base_updated_at:` here for the after-the-fact
    # warning; those screens have no notice area, and Settings moves to an
    # explicit save bar in a later round. That warning is its own state
    # (`:saved_over`, "SAVED · ALSO CHANGED ELSEWHERE -- RELOAD ..."), so the
    # refusal's "● CHANGED ELSEWHERE" always, everywhere, means "not saved".
    def autosave_stream(record:, result:, status_id:, error_prefix:, base_updated_at: nil, fields: {})
      streams = [ turbo_stream.replace(status_id, save_status_component(record: record, result: result, status_id: status_id, base_updated_at: base_updated_at)) ]

      fields.each do |field, attributes|
        messages = Array(attributes).flat_map { |attribute| record.errors.full_messages_for(attribute) }
        streams << turbo_stream.replace(Admin::FieldComponent.error_id(error_prefix, field),
          partial: "admin/shared/field_errors", locals: { id: Admin::FieldComponent.error_id(error_prefix, field), messages: messages })
      end

      # Only bumped on an actual save: a failed attempt never touches the
      # record, so the base the client is holding is still exactly right,
      # and re-sending the same value costs nothing but isn't worth a
      # stream tag either.
      if result.ok?
        base_id = "#{error_prefix}-base-updated-at"
        streams << turbo_stream.replace(base_id, partial: "admin/shared/base_updated_at_field", locals: { id: base_id, value: record.updated_at.iso8601(6) })
      end

      # A failed save also raises an error toast (handoff §10): the status
      # line and the per-field slots can be scrolled out of sight, and an
      # error toast stays until dismissed. It only restates that the save
      # didn't happen -- the reasons stay in the field slots, never here.
      #
      # Precisely because it never auto-hides, it is one toast per form, not
      # one per failed attempt: it carries a stable id, a failure removes the
      # previous one before appending its own (three failed autosaves in a
      # row used to stack three identical toasts), and the next successful
      # save removes it (it used to sit there, claiming a failure that had
      # already been fixed). Removing an id that isn't on the page is a no-op.
      toast_id = "toast-#{error_prefix}"
      streams << turbo_stream.remove(toast_id)
      unless result.ok?
        message = result.denied? ? "You don't have permission to make this change." : "Couldn't save your changes."
        streams << toast_stream(message, kind: :error, id: toast_id)
      end

      streams
    end

    # One toast appended to the layout's `#toasts` region
    # (`Admin::ToastRegionComponent`) from a Turbo Stream answer -- for a
    # response that has no redirect and so no flash to carry the message.
    # `action` is `{ label:, url:, method: }` and `id` the optional DOM id,
    # both as for `Admin::ToastComponent`.
    def toast_stream(message, kind: :success, action: nil, id: nil)
      turbo_stream.append("toasts", Admin::ToastComponent.new(message: message, kind: kind, action: action, id: id))
    end

    # Optimistic locking for the three record editors (the page settings
    # form, a block card, the post form). Each form carries the record's
    # `updated_at` as it loaded it (`base_updated_at`, iso8601 with
    # microseconds); a save sent with a base OLDER than the record as just
    # loaded for this request is refused: 409, the service never called, the
    # record untouched, and the answer is the "● CHANGED ELSEWHERE" status
    # plus the explanation bar in `#editor-notice`
    # (`Admin::EditorScreen::ChangedElsewhereComponent`).
    #
    # This used to be last-write-wins with a warning: the save went through
    # and the status line merely said "Changed elsewhere -- reload". The
    # handoff's rule (§10 B19) is different and only makes sense if the stale
    # write did NOT happen: the editor's text stays on screen so they can
    # copy it, and Reload discards it for the newer version. A warning after
    # an overwrite would offer to throw away text that had already replaced
    # the other editor's.
    #
    # What is NOT done, deliberately: the answer carries no
    # `base_updated_at` replacement (the form keeps its old base, so every
    # later save is refused too -- advancing it would turn the next keystroke
    # into the very overwrite just refused), and no audit event (nothing was
    # attempted through a service, and this is a lost race, not a permission
    # denial -- `access.denied` is for the latter). A blank or unparseable
    # base is not stale: non-JS and scripted clients (and MCP, which does not
    # use this endpoint at all) never send one, and keep saving as before.
    #
    # Accepted race: the check and the save are not atomic (the record is
    # loaded, compared, then written some milliseconds later, with no lock or
    # `WHERE updated_at = base`). Two saves on the same base arriving within
    # the same few milliseconds can both pass and the later one wins. The
    # window is the length of one request, against the human-scale one this
    # guards (another editor's save minutes ago); closing it would need
    # row locking in every service for no case a person can produce.
    #
    # The refusal also removes a lingering failed-save error toast for the
    # form (`toast-<error_prefix>`), as a successful save does: the failure
    # it reports has been superseded by this answer.
    #
    # Returns true after rendering the refusal, so a caller is
    # `return if refuse_stale_autosave(...)` before it calls its service.
    # `record` must be the record as loaded for this request, before any write.
    def refuse_stale_autosave(record, status_id:, error_prefix:, reload_url:)
      return false unless stale_base?(record, params[:base_updated_at])

      render turbo_stream: stale_streams(record, status_id: status_id, error_prefix: error_prefix, reload_url: reload_url, since: Time.iso8601(params[:base_updated_at])), status: :conflict
      true
    end

    def stale_streams(record, status_id:, error_prefix:, reload_url:, since:)
      live = live_record?(record)
      [
        turbo_stream.replace(status_id, Admin::SaveStatusComponent.new(id: status_id, state: :stale, live: live)),
        turbo_stream.update("editor-notice", Admin::EditorScreen::ChangedElsewhereComponent.new(record: record, reload_url: reload_url, since: since)),
        turbo_stream.remove("toast-#{error_prefix}")
      ]
    end

    # The HTTP status an autosave answers with: 200, 403 for a permission
    # refusal (access-control design spec §3.4 -- a forged or stale-tab
    # PATCH to a record the user may only read), 422 for anything else.
    # The Turbo Stream body is sent either way; `admin--autosave` renders a
    # stream answer whatever its status.
    def autosave_status(result)
      if result.ok? then :ok
      elsif result.denied? then :forbidden
      else :unprocessable_entity
      end
    end

    private

    # Whether an edit to `record` goes straight to the site: a live page or
    # post, and a content block whose owner page/post is live (a block is
    # published with its owner, so its save line reads "SAVED TO SITE" like
    # the page's own).
    def live_record?(record)
      record = record.owner if record.is_a?(ContentBlock)
      record.respond_to?(:live?) && record.live?
    end

    # `live:` (a page or post that is live -- its edits go straight to the
    # site) rides on every state, not just "saved": the status line is
    # replaced wholesale, and `autosave_controller.js` reads `data-live`
    # off whatever element is there when it writes its own "saving" line.
    def save_status_component(record:, result:, status_id:, base_updated_at:)
      live = live_record?(record)
      return Admin::SaveStatusComponent.new(id: status_id, state: :forbidden, live: live) if result.denied?
      return Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size, live: live) unless result.ok?

      return Admin::SaveStatusComponent.new(id: status_id, state: :saved_over, live: live) if legacy_stale_after_save?(record, base_updated_at)

      Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: record.updated_at, live: live)
    end

    # The after-the-fact check for the callers that still warn rather than
    # refuse: compared against the value the row had *before this save*
    # (`updated_at_before_last_save`), not `record.updated_at`, which this
    # very save just rewrote and which would make almost every save look
    # stale.
    def legacy_stale_after_save?(record, base_updated_at)
      return false if base_updated_at.blank?

      previous = record.updated_at_before_last_save
      return false if previous.nil?

      Time.iso8601(base_updated_at) < previous
    rescue ArgumentError
      false
    end

    # The record's `updated_at` as loaded for this request is newer than the
    # base the form sent: someone saved it since the form loaded. Blank or
    # unparseable base: not stale (see `#refuse_stale_autosave`).
    def stale_base?(record, base_updated_at)
      return false if base_updated_at.blank?

      Time.iso8601(base_updated_at) < record.updated_at
    rescue ArgumentError
      false
    end
  end
end
