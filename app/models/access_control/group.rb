module AccessControl
  # A named bundle of grants (design spec §3.2) that users belong to
  # (`Membership`) and MCP tokens are scoped to (`ApiToken#group`). Groups
  # carry permissions, not users directly (design spec §2, Craft/TYPO3
  # style) -- the four roles (Admin, Editor, Author, Read only) are seeded
  # groups (`AccessControl::Seeds`), not a closed enum, so a studio admin
  # can add more later without a code change.
  #
  # `table_name` is set explicitly: Rails' default table-name inference
  # demodulizes a namespaced class's name (`AccessControl::Group` would
  # otherwise resolve to `groups`, not `access_control_groups` -- Global
  # Constraints).
  class Group < ApplicationRecord
    self.table_name = "access_control_groups"

    has_many :grants, class_name: "AccessControl::Grant", dependent: :destroy
    has_many :memberships, class_name: "AccessControl::Membership", dependent: :destroy
    has_many :users, through: :memberships

    # No `dependent:` here on purpose. Design spec §3.2: "On group delete
    # the token is revoked" -- that's an application-level action (a
    # later task's `Groups::Destroy` service revokes tokens before the
    # delete), not a cascade. Until that exists, the DB foreign key on
    # `api_tokens.group_id` (no `on_delete` -- see the migration) simply
    # refuses to delete a group any active token still points at.
    has_many :api_tokens, foreign_key: :group_id, inverse_of: :group

    validates :name, presence: true, uniqueness: { case_sensitive: false }

    # `prepend: true`, same reasoning as `User#ensure_not_last_owner`: the
    # `dependent: :destroy` callbacks above (grants, memberships) already
    # registered their own `before_destroy` hooks first, so without this a
    # refused delete would still have destroyed a built-in group's grants
    # and memberships before this check ever ran.
    before_destroy :ensure_not_built_in, prepend: true

    private

    # Built-in groups (design spec §3.2: "Built-in groups can be edited
    # but not deleted") are the ones `AccessControl::Seeds` seeds and every
    # later task assumes exist by name (e.g. `ApiToken.generate!`'s interim
    # default group) -- deleting one out from under that would be a
    # surprise no confirm-dialog warns about. Their grants can still change
    # freely; only the group row itself is protected.
    def ensure_not_built_in
      return unless built_in?

      errors.add(:base, "built-in groups can't be deleted")
      throw :abort
    end
  end
end
