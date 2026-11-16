module Admin
  module Fields
    # A `<select>` of the switched-on content types (spec §4.3), for
    # `:content_type` fields -- e.g. `test/event#speakers`' sibling fields
    # that name *which* content type another post references. Options come
    # from the live `ContentTypes` registry (the types the site has switched
    # on), not a fixed list, the same way
    # a post's own "content type" picker (spec §5.2) would.
    #
    # A `SelectField` subclass, not a sibling `Base` subclass: the two differ
    # in where their options come from (`field.options[:options]` vs
    # `ContentTypes.switched_on`) and in the warning under a stored value the
    # site has not switched on (its own template, the select's plus that line).
    class ContentTypeField < SelectField
      # The stored name as it is, not a select's label lookup.
      def self.display(_field, value) = value.to_s

      def self.own_label?(_field) = false

      # The stored value names a type the site has not switched on (switched
      # off, or no longer declared): the list this filter makes shows nothing.
      def switched_off?
        stored = value.to_s
        stored.present? && ::ContentTypes.switched_on_names.map(&:to_s).exclude?(stored)
      end

      def stored_label = ::ContentTypes.find(value.to_s)&.label || value.to_s

      def list_empty_id = "#{input_id}-list-empty"

      # The help line and, when shown, the empty-list notice.
      def describedby = [ help_id, (list_empty_id if switched_off?) ].compact.join(" ").presence

      # Navigation only: the link is offered to a holder of `settings.manage`.
      def settings? = can?("settings.manage")

      # The switched-on types, then the stored value when it is not one (a
      # switched-off type or a retired name), marked, so a save of the form
      # keeps what it holds instead of silently choosing another type.
      def option_pairs
        pairs = ::ContentTypes.switched_on.map { |definition| [ definition.label, definition.name ] }
        stored = value.to_s
        return pairs if stored.blank? || pairs.any? { |_label, name| name.to_s == stored }

        label = ::ContentTypes.find(stored)&.label || stored
        pairs + [ [ t("admin.components.fields.content_type.switched_off", label:), stored ] ]
      end
    end
  end
end
