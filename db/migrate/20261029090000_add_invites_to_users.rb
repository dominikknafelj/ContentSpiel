# Invites (docs/superpowers/specs/2026-10-28-mail-design.md, "Invites"): an
# invited person is a `users` row in an invited state, not a table of its own.
#
# - `invited_at` set means invited: the row cannot sign in (`User.can_sign_in`
#   leaves it out everywhere people who can sign in are counted or listed).
#   Accepting clears it.
# - `invite_sent_at` is when the last link was sent. The invite token is
#   signed over it (`generates_token_for :invite`), so a resend, which moves
#   it, kills the old link. Accepting keeps it, so a used link still finds its
#   row and the page can say "already used" (plan Ruling 3).
# - `invited_by_id` is who sent the invite; nulled when that user is deleted.
#
# `password_digest` stays NOT NULL: the invited row holds the digest of a
# random password nobody is told (plan Ruling 2).
class AddInvitesToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.datetime :invited_at
      t.datetime :invite_sent_at
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
    end
  end
end
