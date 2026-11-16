module Admin
  module Fields
    # A `<select>` of the switched-on content types (spec §4.3), for
    # `:content_type` fields -- e.g. `test/event#speakers`' sibling fields
    # that name *which* content type another post references. Options come
    # from the live `ContentTypes` registry (the types the site has switched
    # on), not a fixed list, the same way
    # a post's own "content type" picker (spec §5.2) would.
    #
    # A `SelectField` subclass, not a sibling `Base` subclass with its own
    # copy of the same template: the two only ever differed in where their
    # options come from (`field.options[:options]` vs `ContentTypes.switched_on`),
    # so this overrides `option_pairs` alone and reuses `select_field
    # .html.erb` via ViewComponent's own template-inheritance support (a
    # subclass with no sidecar template of its own falls back to its
    # superclass's).
    class ContentTypeField < SelectField
      # The stored name as it is, not a select's label lookup.
      def self.display(_field, value) = value.to_s

      def self.own_label?(_field) = false

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
