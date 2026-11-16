module Admin
  module SettingsScreen
    # The Post types card, after Languages, for `settings.manage`: one switch
    # per DECLARED post type (`::ContentTypes.all`, on or off: a type the site
    # switched off is the row a person turns back on), the type's dot and
    # label, its description and how many kept posts of it the viewer may read.
    # A field of the one Settings form (`site_setting[content_types][]`), saved
    # with its save bar. A hidden empty value precedes the switches, so
    # unticking every one posts an empty list and meets the "keep at least one"
    # error rather than leaving the column alone.
    #
    # - `site_setting` is the SAVED row: `data-stored` on a row says what the
    #   save bar will change it from.
    # - `values` is what the switches show (typed beats stored after a refused
    #   save).
    # - `counts` is `{ type name => kept posts the viewer may read }`, read once
    #   by the controller through the read scope: a count of posts the viewer
    #   cannot read would say they exist.
    # - `errors` is the sentences a refused save gave the field.
    #
    # A row with posts carries the line it says while its switch differs from
    # the stored state, server-drawn and `hidden`, shown by two `:has()` rules
    # (`.admin-post-types__leaving` / `__returning` in content-spiel.tailwind.css)
    # and named in the switch's `aria-describedby`: no controller, no script.
    # A stored name that is no longer declared draws no row; the service carries
    # it through every save.
    class PostTypesCardComponent < Admin::AdminComponent
      FIELD = "site_setting[content_types][]".freeze

      # The first switch's id: where the error summary's link lands.
      def self.first_switch_id = switch_id(::ContentTypes.all.first&.name)

      def self.switch_id(name) = "settings-content_type-#{name}"

      def initialize(section:, site_setting:, counts:, values:, errors: [])
        @section = section
        @site_setting = site_setting
        @counts = counts
        @values = values
        @errors = errors
      end

      def errors_id = "settings-content_types-errors"

      private

      attr_reader :section, :site_setting, :counts, :values, :errors

      # `[[group heading or nil, [definition, ...]], ...]`: the ungrouped types
      # first, then each group in the order its first type registered.
      def bands
        grouped = ::ContentTypes.all.group_by(&:group)
        ungrouped = grouped.delete(nil)
        (ungrouped ? [ [ nil, ungrouped ] ] : []) + grouped.map { |group, definitions| [ t("admin.content_types.groups.#{group}"), definitions ] }
      end

      def stored?(definition) = site_setting.content_types.include?(definition.name.to_s)

      def ticked?(definition) = values.content_types.include?(definition.name.to_s)

      def count(definition) = counts.fetch(definition.name.to_s, 0)

      def switch_id(definition) = self.class.switch_id(definition.name)

      def description(definition) = (t("admin.content_types.descriptions.#{definition.description}") if definition.description)

      # The switch is described by its description alone. The changed-state
      # lines are NOT named: a `hidden` element that `aria-describedby` names
      # is still read, so a switch at rest would announce "leave the site when
      # you save", which is false until the switch is changed.
      def describedby(definition)
        ("#{switch_id(definition)}-description" if definition.description)
      end
    end
  end
end
