module AccessControl
  # Join row between `User` and `Group` (design spec §3.2): who belongs to
  # which group. No attributes of its own beyond the two foreign keys --
  # membership is binary, not itself scoped. A grant's `scope` is what
  # narrows what the group's members may do; which users are members isn't
  # narrowed at all.
  #
  # Cascades at the DB level on either side (the migration's `on_delete:
  # :cascade` on both foreign keys), so destroying a user or a group never
  # leaves an orphaned membership row behind to trip up a later query.
  class Membership < ApplicationRecord
    self.table_name = "access_control_memberships"

    belongs_to :user
    belongs_to :group, class_name: "AccessControl::Group"

    validates :group_id, uniqueness: { scope: :user_id }
  end
end
