# `invited_user("dana@example.com")`: a `users` row in the invited state, as
# `Users::Invite` leaves it (a random password nobody is told, `invited_at`
# and `invite_sent_at` set), built directly so a test of a place that lists
# or counts people needs neither mail nor an actor. `groups:` puts the row in
# those groups, which an invite may do.
module Invites
  def invited_user(email_address = "invited@example.com", name: nil, groups: [], sent_at: Time.current, invited_by: users(:one))
    password = SecureRandom.base58(32)
    user = User.create!(email_address:, name:, password:, password_confirmation: password,
      invited_at: sent_at, invite_sent_at: sent_at, invited_by:)
    groups.each { |group| AccessControl::Membership.create!(user:, group:) }
    user
  end
end
