# Outgoing mail (docs/superpowers/specs/2026-10-28-mail-design.md): the SMTP
# settings the site keeps itself (a host's MAIL_* variables override them
# field by field, see `MailSettings`) and the state of the last sends.
#
# `mail_username` and `mail_password` are text because Active Record
# encryption stores a longer, encoded value (`encrypts` on the model).
# The state columns (`mail_verified_*`, `mail_last_sent_at`, `mail_failed_at`,
# `mail_failure`) are written only by `MailSettings.record_success!` and
# `record_failure!`, with `update_columns`: mail's state is not content.
class AddMailToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    change_table :site_settings, bulk: true do |t|
      t.string :mail_server
      t.integer :mail_port
      t.string :mail_security
      t.string :mail_sender_name
      t.string :mail_sender_address
      t.text :mail_username
      t.text :mail_password
      t.datetime :mail_login_saved_at
      t.datetime :mail_verified_at
      t.string :mail_verified_fingerprint
      t.datetime :mail_last_sent_at
      t.datetime :mail_failed_at
      t.jsonb :mail_failure
    end
  end
end
