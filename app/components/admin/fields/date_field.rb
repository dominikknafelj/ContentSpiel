module Admin
  module Fields
    # A `type="date"` input (spec §4.3), for `:date` fields. `value` may
    # already be a `Date` (a `FieldSet` reader casts it) or an ISO string (a
    # raw Hash from a Lookbook preview or an unsaved form) -- either way the
    # `<input>`'s `value=` needs the ISO string form the HTML date input
    # expects, not `Date#to_s`'s locale-dependent formatting.
    class DateField < Base
      def iso_value = value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end
end
