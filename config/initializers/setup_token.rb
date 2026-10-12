# Prints the setup token while setup is still required, so whoever deployed
# the app can copy it from the server log into /setup (design spec
# 2026-09-26 §3). The line is `Setup::Token.log_line`: a token the operator
# set in SETUP_TOKEN is named by its variable and not printed, the derived
# one is printed because this log is the only place it can be read.
# after_initialize so app constants autoload; the rescue
# covers boots where the database isn't reachable or migrated yet
# (assets:precompile, db:prepare on a brand-new install).
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    if Setup.required?
      Rails.logger.warn Setup::Token.log_line
    end
  rescue ActiveRecord::ActiveRecordError
    nil
  end
end
