# A group an invitation puts its person into when they accept
# (`Invitations::Accept` makes the memberships). Not a membership: until it
# is accepted an invitation is a member of nothing, so no group's member list,
# grant or check sees it. Both foreign keys cascade in the database.
class InvitationGroup < ApplicationRecord
  belongs_to :invitation
  belongs_to :group, class_name: "AccessControl::Group"
end
