# The settings row is a transaction's first lock (`ContentSpiel::LockOrder`),
# checked in development and test against every statement sent. The module
# names no model, so hearing a statement never loads one (which would send
# a statement of its own from inside this subscriber).
if Rails.env.local?
  ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| ContentSpiel::LockOrder.heard(payload) }
end
