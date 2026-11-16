# Turns the error subscriber on for the length of a block
# (`Rails.configuration.x.alerts.errors`, off in the test environment so the
# suite's own handled reports queue nothing), and puts the switch back
# afterwards, also when the block raises.
#
#   with_error_alerts { Rails.error.report(error) }
module ErrorAlerts
  def with_error_alerts
    was = Rails.configuration.x.alerts.errors
    Rails.configuration.x.alerts.errors = true
    yield
  ensure
    Rails.configuration.x.alerts.errors = was
  end
end
