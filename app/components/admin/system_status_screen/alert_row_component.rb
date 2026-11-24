module Admin
  module SystemStatusScreen
    # One alert on System status, on `Admin::Ui::SystemCheckRowComponent`'s
    # grid: the kind as a state chip (an error is danger, a security finding
    # warn), the sentence, then the facts joined by " · ": how often, when it
    # was last seen and its mail state (why it was not mailed when no digest
    # can go, `Alerts::Mailing.blocked_by`). How often counts the alert's
    # own raisings ("Seen once", "Seen 12 times"), never the events inside
    # one: a window alert is raised once, an error once per report.
    #
    # A security row ends with "Show in audit log →", the log narrowed to
    # the alert's own events (`Alerts::Alert#audit_filter`: the one event of
    # an owner change or a token, the counted actions in a window alert's
    # span), never the whole log, when it is handed `audit_path` (the viewer
    # holds `audit.view`), a callable that turns those params into the
    # address.
    #
    # The sentence is `Alerts::Alert#sentence`, the data the model hands up,
    # worded here with this card's keys (the digest mail words the same data
    # with its own). An error's class and place are `<code>`; neither ever
    # holds an exception message, which no alert stores. Times are the site's
    # (the request runs in its zone): a time of today is the clock alone with
    # "today", of the day before "yesterday", any other a date.
    class AlertRowComponent < Admin::AdminComponent
      LINK_CLASS = Admin::Ui::SystemCheckRowComponent::LINK_CLASS
      # An unmailed row's mail state, by why no digest goes (`Alerts::Mailing.blocked_by`).
      NOT_MAILED = { mail_not_set_up: ".no_mail", mail_untested: ".no_mail_untested", mail_failed: ".no_mail_failed", no_address: ".no_address" }.freeze

      def initialize(alert:, mail_blocked_by:, audit_path:)
        @alert = alert
        @mail_blocked_by = mail_blocked_by
        @audit_path = audit_path
      end

      private

      attr_reader :alert

      # Nil for a row with nothing to narrow to: no link to the whole log.
      def audit_href
        return unless alert.security? && @audit_path

        narrowing = alert.audit_filter
        @audit_path.call(narrowing) if narrowing
      end

      def security? = alert.security?

      def chip
        tone = alert.category == "error" ? :danger : :warn
        Admin::Ui::StateChipComponent.new(tone: tone, label: t(".#{alert.category}"))
      end

      def error_sentence?
        alert.kind == "error"
      end

      def values = alert.sentence.values

      # The error line: class, then its place when a frame was the application's.
      def error_class = values[:error_class]

      def error_place = values[:place]

      def sentence
        sentence = alert.sentence
        t(".sentences.#{sentence.key}", **sentence.values)
      end

      def how_often = t(".count", count: alert.occurrences)

      def last_seen
        time = alert.last_seen_at.in_time_zone
        case day_of(time)
        when :today then t(".last_today", time: clock(time))
        when :yesterday then t(".last_yesterday", time: clock(time))
        else t(".last_on", time: I18n.l(time, format: stamp_format(time)))
        end
      end

      def mail_state
        return t(".mailed", time: mailed_time) if alert.mailed_at

        t(NOT_MAILED.fetch(@mail_blocked_by, ".not_mailed"))
      end

      def mail_unavailable? = alert.mailed_at.nil? && !@mail_blocked_by.nil?

      def mailed_time
        time = alert.mailed_at.in_time_zone
        day_of(time) == :today ? clock(time) : I18n.l(time, format: stamp_format(time))
      end

      def clock(time) = I18n.l(time, format: :"admin.time")

      def stamp_format(time) = time.year == Time.zone.now.year ? :"admin.short_datetime" : :"admin.datetime"

      def day_of(time)
        today = Time.zone.now.to_date
        return :today if time.to_date == today

        time.to_date == today - 1 ? :yesterday : :other
      end
    end
  end
end
