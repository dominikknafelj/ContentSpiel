# A gem's sign-in methods (`SignIn::Methods`), replayed through the hook
# `ContentSpiel::Plugins.sign_in_methods`. Inside the application's
# `to_prepare`, like every registry (`studio_modules.rb`, `types.rb`): it runs
# at boot and after each development reload, which unloads the registry, and
# a gem's own `to_prepare` would run before this `reset!` and be wiped. The
# CMS registers no method here: its four are `Session::METHODS`.
Rails.application.config.to_prepare do
  SignIn::Methods.reset!

  # A hook that raises stops the boot, naming its place. On a development
  # reload it is logged: the other initializers' `to_prepare` still run, which
  # a raise here would leave unfilled; a gem's files are not reloaded, so the
  # server is restarted once the gem is corrected.
  begin
    ContentSpiel::Plugins.register_sign_in_methods(SignIn::Methods)
  rescue StandardError => error
    raise unless ThemeFolder.booted?

    Rails.logger.error("[ContentSpiel] #{error.class}: #{error.message}. No gem's sign-in method is registered " \
      "from this hook on. A gem's own files are not reloaded: restart the server after correcting it.")
  end
end
