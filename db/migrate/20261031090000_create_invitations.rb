# Invites (docs/superpowers/specs/2026-10-28-mail-design.md, "Invites"): an
# invitation is NOT a user. It is a row of its own, and accepting it creates
# the user (`Invitations::Accept`), so no query of `users` has to know that
# invitations exist (the owner's choice of 2026-10-30; the spec's "As built"
# says why the first build, a `users` row in an invited state, was replaced).
#
# - `email_address` is normalised as `User`'s is (strip + downcase). Unique
#   among OPEN invitations only (`accepted_at IS NULL`): an accepted one is
#   kept, so its used link still finds it and the page can say "already
#   used", and the address may be invited again once that account is gone.
# - `sent_at` is when the last link was sent. The token is signed over it and
#   the address (`Invitation`'s `generates_token_for :accept`), so a resend,
#   which moves it, kills the old link.
# - `inviter_id` is who sent it, `user_id` the account accepting it created;
#   both are nulled when that user is deleted.
# - The groups the person will join are a join table, never a jsonb list of
#   ids, so a deleted group drops out by the database's cascade.
class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.string :email_address, null: false
      t.string :name
      t.references :inviter, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :sent_at, null: false
      t.datetime :accepted_at
      t.references :user, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :invitations, :email_address, unique: true, where: "accepted_at IS NULL", name: "index_invitations_on_open_email_address"

    create_table :invitation_groups do |t|
      t.references :invitation, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :group, null: false, foreign_key: { to_table: :access_control_groups, on_delete: :cascade }
    end
    add_index :invitation_groups, %i[invitation_id group_id], unique: true
  end
end
