# An account made for an invited address closes that address's open
# invitation (`Invitations::Accounts`, which says why). It hears the audit
# log's after-commit notification, as live editing does
# (config/initializers/editing.rb, which says why the name is a string and
# why the block names the module each time it runs).
ActiveSupport::Notifications.subscribe("audit.content_spiel") do |*, payload|
  Invitations::Accounts.heard(payload[:event])
end
