# Prints the setup token while setup is still required, so whoever deployed
# the app can copy it from the server log into /setup (design spec
# 2026-09-26 §3). after_initialize so app constants autoload; the rescue
# covers boots where the database isn't reachable or migrated yet
# (assets:precompile, db:prepare on a brand-new install).
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    if Setup.required?
      Rails.logger.warn "[ContentSpiel] Setup is not complete. Open /setup and enter this setup token: #{Setup::Token.value}"
    end
  rescue ActiveRecord::ActiveRecordError
    nil
  end
end
