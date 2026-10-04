module Admin
  # The rules of the editor's Schedule dialog, shared by the pages' and the
  # posts' `schedule` actions. They are rules of the DIALOG, not of saving:
  # `Pages::Save`/`Posts::Save` may legitimately set a past `published_at`
  # (imports, "Publish now"), so "pick a time in the future" is enforced here,
  # on the way in, and nowhere deeper.
  #
  # The value is a `datetime-local` string with no zone; `Time.zone.parse` reads
  # it in the site zone because every CS Studio request runs inside
  # `Time.use_zone(site zone)` (`BaseController#use_site_time_zone`). A time
  # inside a spring-forward gap resolves the way ActiveSupport resolves it
  # (moved forward an hour) rather than failing.
  #
  # A refusal travels as `flash[:schedule_error]`, NOT `flash[:alert]`: the
  # toast region renders `alert`, and a form error belongs inside the form
  # (the dialog reopens with it), never in a toast.
  module Scheduling
    BLANK_OR_JUNK = "Choose a date and time".freeze
    MAX_YEARS_AHEAD = 50
    IN_THE_PAST = "Pick a time in the future.".freeze

    private

    # [time, nil] or [nil, message].
    def requested_schedule
      at = begin
        Time.zone.parse(params[:published_at].to_s)
      rescue ArgumentError
        nil
      end

      # An absurd year parses happily but is junk to an editor and can be
      # beyond what Postgres stores (a 500 at the write); nothing is ever
      # scheduled further out than this.
      return [ nil, BLANK_OR_JUNK ] if at.nil? || at > MAX_YEARS_AHEAD.years.from_now
      return [ nil, IN_THE_PAST ] if at <= Time.current

      [ at, nil ]
    end

    def refuse_schedule(message, path)
      flash[:schedule_error] = message
      # Echoed back into the field (the component only accepts the
      # datetime-local shape); capped so a junk value can't bloat the cookie.
      flash[:schedule_value] = params[:published_at].to_s.first(40)
      redirect_to path, status: :see_other
    end
  end
end
