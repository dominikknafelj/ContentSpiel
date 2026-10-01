# Soft delete for the three trashable models (trash spec §3). Deliberately no
# `default_scope`: every place that must hide trashed rows says so -- the
# narrowing points in `AccessControl::Scoping` and `PublicSite::Paths`, plus
# the queries listed in `test/integration/trash_visibility_test.rb`, which
# fails if one of them starts leaking. A `default_scope` would hide rows from
# closure_tree, uniqueness checks, associations and the Trash screen itself
# in ways that are hard to see and harder to undo.
module Trashable
  extend ActiveSupport::Concern

  included do
    belongs_to :trashed_by, class_name: "User", optional: true
    scope :kept, -> { where(trashed_at: nil) }
    scope :trashed, -> { where.not(trashed_at: nil) }
  end

  def trashed? = trashed_at.present?
end
