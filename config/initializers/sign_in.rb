# A host's single sign-on variables that would silently open what it meant to
# close or point sign-in at the wrong place stop the boot in every
# environment (`SignIn::Sso::Provider.check!`, which names the variable and
# never a value). Raised from `after_initialize`, so every test and task that
# loads the application meets it too.
Rails.application.config.after_initialize do
  SignIn::Sso::Provider.check!
end

# A production site with one Turnstile key and not the other has no bot
# check (`SignIn::Protection::BotCheck.current`), which a host who set one meant to
# have: the boot says which variable is missing, by its name and never a
# value. Development and test set neither and say nothing.
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  missing = SignIn::Protection::BotCheck.missing_variable
  Rails.logger.warn("[ContentSpiel] The bot check is off: #{missing} is not set.") if missing

  unset = SignIn::Sso::Provider.missing_variables
  Rails.logger.warn("[ContentSpiel] Single sign-on is off: #{unset.to_sentence(last_word_connector: " and ", two_words_connector: " and ")} #{unset.one? ? "is" : "are"} not set.") if unset.any?
end
