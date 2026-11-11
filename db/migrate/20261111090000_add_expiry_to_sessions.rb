# A session ends: when it was last seen (the idle timeout), when it must end
# whatever happens (the absolute timeout) and how its person signed in. A
# session that exists before this has none of the three and no end, so every
# one is deleted rather than given a made-up expiry; each person signs in
# again. Nobody is connected while a deploy migrates, so the rows go without
# the callbacks a live session's destroy runs (`Session#disconnect_cable`).
class AddExpiryToSessions < ActiveRecord::Migration[8.1]
  def up
    connection.delete("DELETE FROM sessions") # sql: a migration's one-off clear of a table whose model has callbacks that need a live cable
    add_column :sessions, :last_seen_at, :datetime, null: false
    add_column :sessions, :expires_at, :datetime, null: false
    add_column :sessions, :authenticated_with, :string, null: false
    add_index :sessions, :expires_at
    add_index :sessions, :last_seen_at
  end

  def down
    remove_index :sessions, :last_seen_at
    remove_index :sessions, :expires_at
    remove_column :sessions, :authenticated_with
    remove_column :sessions, :expires_at
    remove_column :sessions, :last_seen_at
  end
end
