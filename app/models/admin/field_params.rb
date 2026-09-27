module Admin
  # Turns whatever shape a `groups` field's nested params arrive in --
  # `ActionController::Parameters`/`Hash` keyed by row index
  # (`block[settings][speakers][0][name]`, `...[1][name]`, ...), *or*
  # already a plain Array -- into one ordered Array of plain Hashes, the
  # shape `ContentModel::FieldSet#assign` actually expects for a `groups`
  # field's raw value (its own comment: "a `groups` value must be an Array
  # of Hashes"). Rack's nested-query parser usually hands back a genuine
  # Array for sequential `[0]`, `[1]`, ... keys already, but a row removed
  # client-side (`admin--groups#remove`, which only re-numbers the rows
  # that are left rather than guaranteeing a contiguous 0..n run mid-edit)
  # or a form resubmitted before that renumbering lands can leave gaps --
  # and a genuinely non-sequential key set parses as a Hash instead, not an
  # Array, which `FieldSet#validate_group`'s own shape check would then
  # reject outright as `:invalid`. Sorting by the numeric key before
  # dropping it is what keeps row order intact either way.
  #
  # No block type's settings declare a `groups` field yet (cs-studio spec
  # §5.1/Task 5's own brief) -- this exists now purely so Task 7's post
  # editor (typed `groups` fields on a content type) and any later block
  # type that adds one both call through the same one implementation,
  # rather than each re-deriving "make this an Array" on its own.
  module FieldParams
    module_function

    def normalize(value)
      return [] if value.blank?
      return value.map { |row| normalize_row(row) } if value.is_a?(Array)

      value.to_h.sort_by { |key, _| key.to_s.to_i }.map { |(_, row)| normalize_row(row) }
    end

    def normalize_row(row) = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
  end
end
