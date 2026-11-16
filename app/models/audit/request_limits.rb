module Audit
  # A throttle trip on a CS Studio door is an audit event, `request.limited`.
  # Rails' `rate_limit` instruments `rate_limit.action_controller` on every
  # refused request; `heard` is subscribed to it
  # (`config/initializers/alerts.rb`) and records only the FIRST refusal of a
  # window (`count == to + 1`), so a flood of refused requests is one event,
  # not a row each.
  #
  # NOTHING OF THE REQUEST IS KEPT: the metadata is the limit's name and the
  # door (`controller_path#action`), never the `by` key (an address's digest)
  # nor the `cache_key`. The actor, address and channel are whatever `Current`
  # holds, as for every event.
  #
  # A PUBLIC DOOR RECORDS NOTHING (the search, the suggestions, the forms: a
  # controller with the public wall, `Cookieless`): a visitor's limit is no
  # event of CS Studio's, and a flood of visitors must not fill the log.
  #
  # NEVER RAISES: it runs inside the request that was refused, and an
  # exception here would turn a 429 into a 500. A failure logs its class
  # alone, never its message.
  module RequestLimits
    def self.heard(payload)
      return unless payload[:count] == payload[:to] + 1

      controller = payload[:request].controller_instance
      return if controller.nil? || controller.class < Cookieless

      Audit.record("request.limited", metadata: {
        "limit" => (payload[:name].presence || "default").to_s,
        "door" => "#{controller.controller_path}##{controller.action_name}"
      })
    rescue => error
      Rails.logger.error("[Audit::RequestLimits] not recorded: #{error.class}")
    end
  end
end
