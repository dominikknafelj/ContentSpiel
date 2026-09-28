module AccessControl
  # One permission a `Group` holds, optionally narrowed by scope (design
  # spec §3.2/§3.3). `permission` is a registry key (`AccessControl::
  # Permissions`, e.g. `"posts.edit"`), not a `belongs_to` -- the registry
  # is in-memory and code-defined, reset and re-registered on every reload
  # (`config/initializers/types.rb`), so there is no row in the database
  # for a foreign key to point at.
  #
  # `scope` is jsonb, `{}` by default -- an empty scope matches everything
  # the permission's own `scopes` could otherwise narrow, i.e. no
  # restriction at all (`#scope_content_types`/`#scope_page_ids` return an
  # empty array and `#scope_own?` is false for an absent key, which the
  # matcher in a later task reads as "not restricted by this dimension").
  # Its keys are the JSON side of the registry's own scope symbols
  # (`SCOPE_KEY_FOR`): `content_type` -> `"content_types"` (array of
  # content-type name strings), `branch` -> `"page_ids"` (array of page
  # ids, each a branch root, matched via `page_hierarchies` by a later
  # task), `own` -> `"own"` (boolean).
  #
  # A grant is only valid if every key actually present in `scope` is one
  # the matching permission declares among its own `scopes` -- e.g.
  # `page_ids` on `posts.edit` (a `content_type`/`own`-scoped permission,
  # never `branch`) is rejected outright rather than silently ignored, so a
  # typo'd or copy-pasted grant fails loudly in the group editor instead of
  # quietly matching more (or less) than intended.
  class Grant < ApplicationRecord
    self.table_name = "access_control_grants"

    belongs_to :group, class_name: "AccessControl::Group"

    # Global Constraints: "The grant scope maps permission scopes to JSON
    # keys: content_type -> content_types, branch -> page_ids, own -> own."
    SCOPE_KEY_FOR = { content_type: "content_types", branch: "page_ids", own: "own" }.freeze

    validates :permission, presence: true
    validate :permission_is_registered
    validate :scope_keys_are_allowed_by_the_permission
    validate :scope_values_are_well_formed

    # The registered `AccessControl::Permission` this grant's key names, or
    # nil for a stale grant whose key no longer exists (e.g. a removed
    # plugin's permission). `.find`, not `.fetch`: a stale grant must never
    # raise (Global Constraints, review focus #3 -- "a grant scoped to a
    # content type no longer registered... is never an error"), it just
    # matches nothing.
    def permission_definition = AccessControl::Permissions.find(permission)

    def scope_content_types = Array(scope["content_types"])
    def scope_page_ids = Array(scope["page_ids"]).map(&:to_i)
    def scope_own? = ActiveModel::Type::Boolean.new.cast(scope["own"])

    private

    def permission_is_registered
      return if permission.blank? || permission_definition

      errors.add(:permission, "isn't a registered permission")
    end

    def scope_keys_are_allowed_by_the_permission
      return unless permission_definition

      allowed_keys = permission_definition.scopes.map { |scope_kind| SCOPE_KEY_FOR.fetch(scope_kind) }
      disallowed_keys = scope.keys - allowed_keys
      return if disallowed_keys.empty?

      errors.add(:scope, "can't be scoped by #{disallowed_keys.join(", ")} for #{permission}")
    end

    def scope_values_are_well_formed
      if scope.key?("content_types") && !array_of?(scope["content_types"], String)
        errors.add(:scope, "content_types must be an array of strings")
      end

      if scope.key?("page_ids") && !array_of?(scope["page_ids"], Integer)
        errors.add(:scope, "page_ids must be an array of integers")
      end

      if scope.key?("own") && ![ true, false ].include?(scope["own"])
        errors.add(:scope, "own must be true or false")
      end
    end

    def array_of?(value, klass)
      value.is_a?(Array) && value.all? { |item| item.is_a?(klass) }
    end
  end
end
