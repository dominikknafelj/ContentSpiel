# A production site with one Turnstile key and not the other has no bot
# check (`SignIn::BotCheck.current`), which a host who set one meant to
# have: the boot says which variable is missing, by its name and never a
# value. Development and test set neither and say nothing.
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  missing = SignIn::BotCheck.missing_variable
  Rails.logger.warn("[ContentSpiel] The bot check is off: #{missing} is not set.") if missing
end
