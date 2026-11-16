module Admin
  module SystemStatusScreen
    # One alert on System status, on `Admin::Ui::SystemCheckRowComponent`'s
    # grid: the kind as a state chip (an error is danger, a security finding
    # warn), the sentence, then the facts joined by " · ": how often, when it
    # was last seen and its mail state. A security row ends with the link to
    # the audit log, where the finding came from.
    #
    # The sentence is `Alerts::Alert#sentence`, the data the model hands up,
    # worded here with this card's keys (the digest mail words the same data
    # with its own). An error's class and place are `<code>`; neither ever
    # holds an exception message, which no alert stores. Times are the site's
    # (the request runs in its zone): a time of today is the clock alone with
    # "today", of the day before "yesterday", any other a date.
    class AlertRowComponent < Admin::AdminComponent
      LINK_CLASS = Admin::Ui::SystemCheckRowComponent::LINK_CLASS

      def initialize(alert:, mail_ready:, audit_href:)
        @alert = alert
        @mail_ready = mail_ready
        @audit_href = audit_href
      end

      private

      attr_reader :alert, :audit_href

      def security? = alert.security?

      def chip
        security? ? Admin::Ui::StateChipComponent.new(tone: :warn, label: t(".security")) : Admin::Ui::StateChipComponent.new(tone: :danger, label: t(".error"))
      end

      def error_sentence?
        alert.kind == "error"
      end

      def values = alert.sentence.values

      # The error line: class, then its place when a frame was the application's.
      def error_class = values[:error_class]

      def error_place = values[:place]

      def sentence
        values = self.values
        key = case alert.kind
        when "owner_changed" then "owner_#{values[:now_owner] ? "made" : "removed"}#{"_by" if values[:actor_name]}"
        when "token_issued" then values[:actor_name] ? "token_issued_by" : "token_issued"
        else alert.kind
        end
        options = values.merge(minutes: Alerts::Alert::WINDOW.in_minutes.to_i)
        count = { "request_limited" => values[:limited], "access_denied_burst" => values[:actors] }[alert.kind]
        options[:count] = count if count
        t(".sentences.#{key}", **options)
      end

      def how_often = t(".occurrences", count: alert.occurrences)

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

        @mail_ready ? t(".not_mailed_yet") : t(".not_mailed_no_mail")
      end

      def mail_unavailable? = alert.mailed_at.nil? && !@mail_ready

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
