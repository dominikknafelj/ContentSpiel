# What a session keeps of the sign-in provider that made it: the refresh token
# (encrypted, `Session`) and when the provider last confirmed the person.
class AddProviderCheckToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :provider_token, :text
    add_column :sessions, :provider_checked_at, :datetime
  end
end
