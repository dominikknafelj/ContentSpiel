module Admin
  # The stale-save rule of the explicit-save screens (Settings, a group, a user):
  # the form carries the record's `updated_at` as it loaded (`base_updated_at`,
  # iso8601 with microseconds, the `admin/shared/base_updated_at_field` partial),
  # and a Save whose base is older than the record as just loaded is REFUSED --
  # answered 409 with the screen re-rendered (`render_stale`), the typed values
  # still in the form, before any service is called, so nothing is written and
  # nothing is audited. The autosaving editors have their own, stream-shaped
  # version of the same comparison (`AutosaveResponses#refuse_stale_autosave`).
  #
  # A blank or unparseable base is NOT stale: non-JS and scripted clients never
  # send one, and a form saved as rendered always carries a good one.
  #
  # The check and the save are not atomic: two Saves on the same base within one
  # request's length can both pass.
  #
  # A record the viewer may not change is not this concern's to refuse: the
  # group and user editors skip the check for a group that is view-only for the
  # viewer and a user who is not `:editable`, so a forged write reaches the
  # service and gets its 403 and its one `access.denied` rather than a 409 that
  # records nothing (and would name who last changed the record).
  #
  # Whether a screen's `updated_at` moves for every change the form shows is the
  # services' job (`Groups::Save` touches its members, `Users::Save` its groups,
  # and so on), not this concern's.
  module StaleForm
    # The second sentence of every stale banner, named or not.
    STALE_ADVICE = "Reload to see the latest — your changes are still in the form.".freeze

    private

    def stale_form?(record, base)
      return false if base.blank?

      Time.iso8601(base.to_s) < record.updated_at
    rescue ArgumentError
      false
    end

    # Re-renders `template` at 409 with `@stale_form` set: the view draws the
    # banner (`admin/shared/_stale_banner`) and counts the typed values as
    # unsaved changes (`save_bar_form_data(dirty: ...)`), and the form's hidden
    # base keeps the STALE base it was posted with (the views read
    # `params[:base_updated_at]` first), so a second Save is refused too until
    # Reload.
    #
    # `@stale_change` is who changed `record` since that base and when, for the
    # banner to name: `Audit::ChangeSince`, the rule the autosaving editors' bar
    # uses (someone else's newest change preferred, the viewer's own other tab
    # said as such, nil when no event after the base names this record -- then
    # the banner is the screen's plain `STALE_MESSAGE`). Call it only after
    # `stale_form?` answered true: the base is parseable then.
    def render_stale(template, record)
      @stale_form = true
      @stale_change = Audit::ChangeSince.for(record, since: Time.iso8601(params[:base_updated_at].to_s), viewer: Current.user)
      render template, status: :conflict
    end
  end
end
