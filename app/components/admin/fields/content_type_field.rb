module Admin
  module Fields
    # A `<select>` of every registered content type (spec §4.3), for
    # `:content_type` fields -- e.g. `test/event#speakers`' sibling fields
    # that name *which* content type another post references. Options come
    # from the live `ContentTypes` registry, not a fixed list, the same way
    # a post's own "content type" picker (spec §5.2) would.
    #
    # A `SelectField` subclass, not a sibling `Base` subclass with its own
    # copy of the same template: the two only ever differed in where their
    # options come from (`field.options[:options]` vs `ContentTypes.all`),
    # so this overrides `option_pairs` alone and reuses `select_field
    # .html.erb` via ViewComponent's own template-inheritance support (a
    # subclass with no sidecar template of its own falls back to its
    # superclass's).
    class ContentTypeField < SelectField
      def option_pairs = ContentTypes.all.map { |definition| [ definition.label, definition.name ] }
    end
  end
end
