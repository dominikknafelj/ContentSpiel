# When a session last proved its person (`Session#confirmed_recently?`), and
# whether it must add a passkey before anything else (`enrolment_due`, set at
# sign-in from the policy). The policy itself is nullable: nil is the
# environment's default (`SiteSetting#effective_passkey_policy`), so an
# existing site needs no backfill. An existing session has no confirmation
# time, so Confirm it's you asks it once.
class AddPasskeyPolicyAndConfirmation < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :confirmed_at, :datetime
    add_column :sessions, :enrolment_due, :boolean, null: false, default: false
    add_column :site_settings, :passkey_policy, :string
  end
end
