module Admin
  # A time as a short relative phrase, the absolute time as its tooltip
  # (design pass spec §4): `<time datetime="…" title="3 Oct 2026, 14:05">2h
  # ago</time>`. Everything is read in `Time.zone` -- the site time zone
  # `Admin::BaseController#use_site_time_zone` sets for the request -- so
  # "yesterday" is the site's calendar day, not UTC's, and the tooltip
  # agrees with the audit and dashboard's own `strftime`s. Never `Time.now`:
  # `Time.zone.now` is what `travel_to` and the zone both govern.
  #
  # Breakpoints: under a minute "just now"; under 24 h and still today
  # "Nm ago" / "Nh ago"; a time on the previous calendar day "yesterday"
  # (even when it is less than 24 h ago -- 23:50 last night is yesterday at
  # 00:10); under 7 days "Nd ago"; this year "5 Sep"; older "5 Sep 2025". A
  # future time (a scheduled publish) is an absolute "5 Oct, 09:30".
  # Rendered once per request: lists reload on navigation, so no ticking.
  class TimeAgoComponent < AdminComponent
    # `title:` replaces the tooltip (the dashboard's coalesced edit burst
    # shows its whole span there).
    def initialize(time:, title: nil)
      @time = time&.in_time_zone
      @title = title
    end

    def render? = !time.nil?

    def call
      tag.time(phrase, datetime: time.iso8601, title: @title || I18n.l(time, format: :"admin.datetime"))
    end

    private

    attr_reader :time

    def phrase
      now = Time.zone.now
      return I18n.l(time, format: time.year == now.year ? :"admin.short_datetime" : :"admin.datetime") if time > now

      seconds = now - time
      return t(".just_now") if seconds < 1.minute
      return t(".minutes_ago", count: (seconds / 1.minute).floor) if seconds < 1.hour && time.to_date == now.to_date
      return t(".hours_ago", count: (seconds / 1.hour).floor) if seconds < 1.day && time.to_date == now.to_date
      return t(".yesterday") if time.to_date == now.to_date - 1
      days = (now.to_date - time.to_date).to_i
      return t(".days_ago", count: days) if days < 7
      return I18n.l(time, format: :"admin.short") if time.year == now.year

      I18n.l(time, format: :"admin.short_with_year")
    end
  end
end
