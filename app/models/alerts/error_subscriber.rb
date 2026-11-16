module Alerts
  # What an error report (`Rails.error`) becomes: one log line, an event on
  # the current span and an `Alerts::RecordErrorJob`, each holding the error's
  # class, its place in the code and the report's source, never its message,
  # which may quote what a request carried (a parameter, an address, a typed
  # email). Rails' own request log keeps an unhandled exception's message for
  # whoever reads the server log.
  #
  # Registered in `config/initializers/alerts.rb`, which hands it a report
  # only while `Rails.configuration.x.alerts.errors` is on.
  class ErrorSubscriber
    # The Rails root as a frame starts with it, and the gems a bundle may
    # install under it, which are not the application's code.
    ROOT = "#{Rails.root}/".freeze
    VENDOR = "#{ROOT}vendor/".freeze
    FRAME = /\A(?<path>.+?):(?<line>\d+)(?::|\z)/

    # The first frame of the error's backtrace inside the application, as
    # `app/models/page.rb:120`, or nil when it has none there (or no
    # backtrace at all).
    def self.place_for(error)
      Array(error.backtrace).each do |frame|
        next unless frame.start_with?(ROOT) && !frame.start_with?(VENDOR)

        match = FRAME.match(frame.delete_prefix(ROOT)) or next
        return "#{match[:path]}:#{match[:line]}"
      end
      nil
    end

    # Rails' subscriber interface. It never raises: a subscriber that raises
    # takes the reporter's own error path, and the database an enqueue needs
    # may be the very thing that is down. A failure is one log line with the
    # two classes.
    def report(error, handled:, severity:, context:, source:)
      return if answered_with_4xx?(error) || alerts_job?(context)

      place = self.class.place_for(error)
      Rails.logger.public_send(handled ? :warn : :error,
        "[ContentSpiel] Error reported: #{error.class.name}#{" at #{place}" if place} (#{source})")
      Telemetry.error_event(error_class: error.class.name, place: place)
      RecordErrorJob.perform_later(error_class: error.class.name, place: place, source: source, handled: handled, at: Time.current)
    rescue StandardError => failure
      Rails.logger.error("[ContentSpiel] Error report not recorded: #{error.class.name} (#{failure.class.name})")
    end

    private

    # A not found, a bad request, a stale form: what Rails answers with a 4xx
    # is a visitor's doing, not the site's fault.
    def answered_with_4xx?(error)
      ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500
    end

    # Solid Queue reports a failed job after its `perform`, through the
    # executor, with the job in the context; a guard set inside `perform`
    # would be gone by then. Dropping every job of this namespace keeps a
    # broken database from chaining one RecordErrorJob after another, and a
    # check that fails every minute while the database is down from adding
    # one alert a minute.
    def alerts_job?(context)
      job = context[:job]
      job.is_a?(ActiveJob::Base) && job.class.name.to_s.start_with?("Alerts::")
    end
  end
end
