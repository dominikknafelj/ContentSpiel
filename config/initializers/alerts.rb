# Error reports become alerts (`Alerts::ErrorSubscriber`). The subscriber is
# registered in every environment and acts only while
# `config.x.alerts.errors` is on: on by default (`config/application.rb`),
# off in the test environment, so the suite's own handled reports queue
# nothing, and turned on around a test by `with_error_alerts`. It names
# `Alerts::ErrorSubscriber` at each report, so a development reload is
# followed. Subscribed once per process: an initializer runs once.
Rails.error.subscribe(Object.new.tap do |subscriber|
  def subscriber.report(error, handled:, severity:, context:, source:)
    return unless Rails.configuration.x.alerts.errors

    Alerts::ErrorSubscriber.new.report(error, handled: handled, severity: severity, context: context, source: source)
  end
end)
