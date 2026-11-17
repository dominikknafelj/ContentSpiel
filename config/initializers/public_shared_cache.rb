# PUBLIC_SHARED_CACHE_SECONDS, how long a shared cache may keep a public page
# (`PublicSite::SharedCache`), is read when the application starts, and a
# value that is not a whole number of 0 or more stops the boot in every
# environment, naming the variable. From `after_initialize`, so every test
# and task that loads the application meets it too, as it meets the single
# sign-on check (`config/initializers/sign_in.rb`).
Rails.application.config.after_initialize do
  PublicSite::SharedCache.check!
end
