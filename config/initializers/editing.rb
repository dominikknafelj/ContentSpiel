# Live refresh hears the audit log (live-editing spec §3.1). The notification
# is named by its string, not by `Audit::NOTIFICATION`, so that no application
# constant is loaded while Rails boots; `test/models/editing/signals_test.rb`
# ("a block's save signals its page") fails if the two ever differ. The block
# names `Editing::Signals` each time it runs, so a development reload is
# followed. Subscribed once per process: an initializer runs once.
ActiveSupport::Notifications.subscribe("audit.content_spiel") do |*, payload|
  Editing::Signals.heard(payload[:event])
end
