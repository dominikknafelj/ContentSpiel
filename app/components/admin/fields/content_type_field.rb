module Admin
  module Fields
    # A `<select>` of every registered content type (spec §4.3), for
    # `:content_type` fields -- e.g. `test/event#speakers`' sibling fields
    # that name *which* content type another post references. Options come
    # from the live `ContentTypes` registry, not a fixed list, the same way
    # a post's own "content type" picker (spec §5.2) would.
    class ContentTypeField < Base
      def option_pairs = ContentTypes.all.map { |definition| [ definition.label, definition.name ] }
    end
  end
end
