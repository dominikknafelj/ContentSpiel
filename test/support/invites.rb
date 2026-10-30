# `open_invitation("dana@example.com")`: an open `Invitation`, as
# `Invitations::Invite` leaves it, built directly so a test needs neither mail
# nor an actor. `groups:` are the groups accepting puts the person into.
module Invites
  def open_invitation(email_address = "invited@example.com", name: nil, groups: [], sent_at: Time.current, inviter: users(:one))
    Invitation.create!(email_address:, name:, sent_at:, inviter:).tap do |invitation|
      groups.each { |group| invitation.invitation_groups.create!(group:) }
    end
  end
end
