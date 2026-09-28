# Namespace for access control (design spec §3): a permission registry
# (`AccessControl::Permissions`) that built-ins and, later, plugins register
# against, plus -- from later tasks in this sub-project -- the groups and
# grants that assign those permissions to users and the checker that
# decides whether an actor may act (`AccessControl.allowed?`/`.scope`).
# This task (Task 1) is the registry only: `AccessControl::Permission`,
# `AccessControl::Permissions` and `AccessControl::BuiltIns`.
module AccessControl
  # Raised by `Permissions.register` for a key that's already registered
  # (design spec §3.1) -- a developer error caught at boot, mirroring
  # `ContentModel::DuplicateType`/`RichText::DuplicateType`. The one
  # legitimate re-registration, a `to_prepare` reload, always calls
  # `Permissions.reset!` first (config/initializers/types.rb), so this only
  # fires for an actual duplicate, e.g. two plugins claiming the same key.
  class DuplicatePermission < StandardError; end

  # Raised by `Permissions.fetch` for a key that isn't registered, mirroring
  # `ContentModel::UnknownType`. `.find` is the non-raising counterpart, for
  # call sites (grant validation against a stale grant whose permission key
  # names a removed plugin's permission) that treat "unknown" as a fact of
  # life to route around rather than a bug to raise on.
  class UnknownPermission < KeyError; end
end
