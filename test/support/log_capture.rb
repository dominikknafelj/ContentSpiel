# Everything logged in a block, as one string.
#
# `Rails.logger` alone is not it: the frameworks were handed the logger
# object at boot and keep it, so swapping `Rails.logger` captures the lines
# of a request's start ("Started GET ...", which `Rails::Rack::Logger` asks
# `Rails.logger` for each time) and nothing a mailer, a job or a controller
# writes. Every owner named is swapped for the length of the block and put
# back, also when the block raises.
#
# - `LOGGERS`: the path of a mail (the mailer and the job that delivers it).
# - `REQUEST_LOGGERS`: a request as well: Action Controller's own lines
#   ("Processing by ...", "Parameters: ...", "Redirected to ..."), Action
#   View's, and what Action Dispatch writes for a request that raises or
#   has no route ("ActionController::RoutingError (No route matches ...)"),
#   whose logger is not a class's but an entry of the application's
#   memoised Rack environment (`DISPATCH`).
module LogCapture
  # `action_dispatch.logger`, as an owner with `logger` and `logger=`. Read
  # (and so memoised by Rails with the real logger) before anything is
  # swapped: the first request of a process inside a capture would otherwise
  # leave the capture's logger there for good.
  DISPATCH = Object.new.tap do |owner|
    def owner.logger = Rails.application.env_config["action_dispatch.logger"]
    def owner.logger=(logger)
      Rails.application.env_config["action_dispatch.logger"] = logger
    end
  end

  LOGGERS = [ Rails, ActionMailer::Base, ActiveJob::Base ].freeze
  REQUEST_LOGGERS = [ DISPATCH, *LOGGERS, ActionController::Base, ActionView::Base ].freeze

  def capture_log(owners = LOGGERS)
    were = owners.map(&:logger)
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    owners.each { |owner| owner.logger = logger }
    yield
    io.string
  ensure
    owners.zip(were) { |owner, was| owner.logger = was }
  end
end
