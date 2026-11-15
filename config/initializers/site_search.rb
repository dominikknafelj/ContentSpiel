# The public site's search backends (`SiteSearch::Backends`): the built-in,
# then a gem's, replayed through the hook `ContentSpiel::Plugins.search_backends`.
# Inside the application's `to_prepare`, like every registry
# (`sign_in_methods.rb`, `studio_modules.rb`): it runs at boot and after each
# development reload, which unloads the registry, and a gem's own
# `to_prepare` would run before this `reset!` and be wiped. The built-in's
# class is named inside its callable, which is called only when the backend
# is first asked for (`SiteSearch::Backends.current`).
Rails.application.config.to_prepare do
  SiteSearch::Backends.reset!
  SiteSearch::Backends.register "postgres", label: "Postgres", backend: -> { SiteSearch::Postgres.new }, inline: true

  # A hook that raises, or a SEARCH_BACKEND no backend registered, stops the
  # boot, naming the place or the registered names. On a development reload
  # it is logged: the other initializers' `to_prepare` still run, which a
  # raise here would leave unfilled, and a search the chosen backend cannot
  # answer is unavailable; a gem's files are not reloaded, so the server is
  # restarted once the gem is corrected.
  begin
    ContentSpiel::Plugins.register_search_backends(SiteSearch::Backends)
    SiteSearch::Backends.check!
  rescue StandardError => error
    raise unless ThemeFolder.booted?

    Rails.logger.error("[ContentSpiel] #{error.class}: #{error.message}. A search backend after the error is not registered, " \
      "and a search its backend cannot answer is unavailable. A gem's own files are not reloaded: restart the server after correcting it.")
  end
end

# The boot names the chosen backend, and in a process that serves requests
# enqueues the index check, which builds the index when it is empty or stale
# (`SiteSearch::BootCheck`, spec §6.6). After the `to_prepare` above, which
# filled the registry. A boot never fails because of search: `run` rescues
# its own enqueue, and the line is skipped if it cannot be written.
Rails.application.config.after_initialize do
  begin
    Rails.logger.info(SiteSearch::BootCheck.log_line)
  rescue StandardError
    nil
  end
  SiteSearch::BootCheck.run
end
