# An invitation to a person who has no account yet (mail spec "Invites";
# docs/reference/mail.md). It is NOT a user: it lives in its own table, and
# accepting it creates the user (`Invitations::Accept`). So no query of
# `users` -- sign-in, the reset, the owner checks, mentions, a group's member
# picker, the audit log's people filter -- has to know that invitations
# exist, and a new one never has to remember to leave them out (the owner's
# choice of 2026-10-30, replacing an invited state on `users`; the spec's "As
# built" says why). Nothing of the users side names this class
# (`test/lib/mail_guards_test.rb`).
#
# Its life:
#   open      `accepted_at` nil: listed on the Users screen with its dates,
#             its link works until `expires_at`; at most one open invitation
#             per address (a partial unique index).
#   accepted  `accepted_at` set and `user` the account it made. The row is
#             kept: its link still finds it, so the page says "already used"
#             rather than "expired" for the seven days the token is good.
#   withdrawn the row is deleted, with its groups (the join rows cascade):
#             the link finds nothing and the page says "expired".
#
# `groups` are the groups the person will be put into when they accept; an
# invitation is a member of nothing until then.
class Invitation < ApplicationRecord
  # How long a link works (spec: seven days). The mail names the date from
  # this, so the token and the sentence cannot disagree.
  VALID_FOR = 7.days

  # Signed over `sent_at` and `email_address` (plan Ruling 3 and controller
  # ruling F1): a resend moves `sent_at`, so the old link dies; a withdrawal
  # deletes the row, so nothing is found; an address changed on the row
  # would kill the link mailed to the old one. Accepting changes NEITHER, so a
  # used link still finds its row. The token is made only by `InvitesMailer`,
  # in the job: no token is ever an argument of a mailer or a job.
  generates_token_for(:accept, expires_in: VALID_FOR) { [ sent_at, email_address ] }

  # Who sent it, and the account accepting it made; both nulled by the
  # database when that user is deleted.
  belongs_to :inviter, class_name: "User", optional: true
  belongs_to :user, optional: true
  # The join rows go with the invitation by the database's cascade.
  has_many :invitation_groups
  has_many :groups, through: :invitation_groups, class_name: "AccessControl::Group"

  # As `User`'s, so an address is compared as it would be stored on the
  # account the invitation makes.
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(name) { name.to_s.strip.presence }

  validates :email_address, presence: true
  validates :name, length: { maximum: 120 }

  scope :open, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  def open? = accepted_at.nil?
  def accepted? = !open?

  # Its link can make no account any more: it was accepted, or the address
  # has an account by now (made on the New user form meanwhile). The person
  # signs in instead, so the accept page says "already used" for both.
  def used? = accepted? || User.exists?(email_address: email_address)

  # When the current link stops working: seven days after it was sent.
  def expires_at = sent_at && sent_at + VALID_FOR

  # Lapsed: the link no longer works, and the Users screen says so.
  def expired?(now: Time.current) = expires_at.nil? || expires_at <= now

  # The invited person's name, else the address: how the Users screen and
  # the dialogs name an invitation.
  def display_name = name.presence || email_address
end
