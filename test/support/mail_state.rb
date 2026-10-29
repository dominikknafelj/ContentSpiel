# Puts the site's mail settings in one of the four states for the length of a
# block, and puts the columns back afterwards, also when the block raises.
#
#   with_mail_state(:working) { ... }
#   with_mail_state(:untested, mail_server: "smtp.other.test") { ... }
#
# The states (`MailSettings#state`):
#
#   :not_set_up  server, port and sender address are empty. Incomplete in
#                every environment, the stand-in included (a sender address
#                is always needed).
#   :untested    server smtp.example.test, port 587, STARTTLS, sender address
#                no-reply@example.test, nothing verified.
#   :working     :untested, verified now with the fingerprint of exactly
#                these settings, last mail sent a minute ago.
#   :failed      :working, and a failure after the last success (a refused
#                login), so `ready?` is still true.
#
# `settings` are column values (`mail_server:`, `mail_sender_name:` ...) that
# replace the state's own, applied BEFORE the fingerprint is taken, so
# `:working` with a different server is verified for that server.
#
# The columns are written with `update_columns` (no callback, no content
# version, as the app writes them) and `Current.site` is dropped on both
# sides so no cached row hides the change. A host variable is not touched:
# a test of one passes `env:` to `MailSettings.current` itself.
module MailState
  COLUMNS = %w[
    mail_server mail_port mail_security mail_sender_name mail_sender_address
    mail_username mail_password mail_login_saved_at mail_verified_at
    mail_verified_fingerprint mail_last_sent_at mail_failed_at mail_failure
  ].freeze

  COMPLETE = {
    "mail_server" => "smtp.example.test", "mail_port" => 587, "mail_security" => "starttls",
    "mail_sender_name" => "Test Site", "mail_sender_address" => "no-reply@example.test"
  }.freeze

  def with_mail_state(state, **settings)
    site = SiteSetting.instance
    saved = COLUMNS.index_with { |name| site.read_attribute_before_type_cast(name) }
    site.update_columns(COLUMNS.index_with { nil }) # version: none (a test helper)
    columns = mail_state_columns(state).merge(settings.stringify_keys)
    site.update_columns(columns) if columns.any? # version: none (a test helper)
    if %i[working failed].include?(state)
      site.update_columns( # version: none (a test helper)
        mail_verified_fingerprint: MailSettings.current(site.reload, env: {}).fingerprint
      )
    end
    Current.site = nil
    yield
  ensure
    if saved
      SiteSetting.instance.update_columns(saved) # version: none (a test helper)
      Current.site = nil
    end
  end

  private

  def mail_state_columns(state)
    case state
    when :not_set_up then {}
    when :untested then COMPLETE
    when :working
      COMPLETE.merge("mail_verified_at" => 2.minutes.ago, "mail_last_sent_at" => 1.minute.ago)
    when :failed
      COMPLETE.merge("mail_verified_at" => 3.minutes.ago, "mail_last_sent_at" => 3.minutes.ago,
        "mail_failed_at" => 1.minute.ago, "mail_failure" => { "key" => "login", "line" => "535 5.7.8 Authentication failed" })
    else raise ArgumentError, "unknown mail state #{state.inspect}"
    end
  end
end
