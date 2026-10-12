# Rack middleware, at the head of the stack: takes a password-reset token
# out of the address of a request before anything of Rails has read it.
#
# The reset link carries its token after a "#" now, which no server is sent
# (`PasswordsMailer#reset_url`, `Admin::PasswordsController`). But the old
# link had it in the path, `<admin>/password/<token>/edit`, and so had the
# old form's address, `<admin>/password/<token>`; a mail sent before the
# change, and a form opened before it, still ask for those for the fifteen
# minutes a token is good, and anybody can go on sending them.
#
# A route that only redirects does not keep such a path out of the log.
# Rails writes it down before the router is asked: the first line of every
# request ("Started GET ..."), and for an address with no route (the old
# form's) the error line too ("No route matches [PATCH] ..."). Neither is a
# parameter, so `filter_parameters` reaches neither. So the segment is
# replaced here, at the door, in every place Rack and Rails keep the
# address; what follows (the logger, the router, an error page, whatever is
# added later) sees `<admin>/password/[FILTERED]/edit`, which the router
# still takes for the old link and answers with its redirect.
#
# Which paths: `Telemetry::PathScrubber`'s rule, the one that masks the
# same segment in a span (it says why the rule is wider than the two
# routes). The address of the form as it is now, `<admin>/password/edit`,
# and `<admin>/password/new` are left as they are.
#
# NOT COVERED, and not coverable from here: what stands in front of the
# application. The proxy's access log has the path as the client sent it.
# And where telemetry is on, OpenTelemetry's own Rack middleware puts itself
# ahead of this one and reads the path as it came: its spans are scrubbed
# by the same rule on their way out (config/initializers/opentelemetry.rb).
#
# `config/application.rb` requires this file: a middleware is named while
# the application is configured, before the autoloader is set up.
class OldResetAddress
  # `PATH_INFO` is what the router and the request's first log line read;
  # `ORIGINAL_FULLPATH` is Rails' copy of it (`request.original_fullpath`,
  # and so `original_url`), made before the first middleware runs;
  # `REQUEST_URI` and `REQUEST_PATH` are the web server's own.
  KEYS = %w[PATH_INFO ORIGINAL_FULLPATH REQUEST_URI REQUEST_PATH].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    KEYS.each do |key|
      value = env[key]
      scrubbed = Telemetry::PathScrubber.scrub(value)
      env[key] = scrubbed unless scrubbed.equal?(value)
    end

    @app.call(env)
  end
end
