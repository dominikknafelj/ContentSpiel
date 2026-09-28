# One registered permission (design spec §3.1): its key, the label and area
# the group editor groups it under, the record class it governs (`nil` for
# an admin-area permission with no single subject, e.g. `users.manage`),
# its action, and which scopes (a subset of `content_type`/`branch`/`own`)
# a grant may narrow it by.
#
# A plain `Data`, not a builder-style `ContentModel::Definition` subclass --
# unlike a content or block type, a permission has no nested schema to
# accumulate through a DSL block. `AccessControl::Permissions.register`
# takes every field as a keyword argument and builds the finished, frozen
# value directly.
module AccessControl
  Permission = Data.define(:key, :label, :area, :subject, :action, :scopes)
end
