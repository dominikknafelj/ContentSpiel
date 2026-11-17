module Admin
  module SettingsScreen
    # The Page speed card, last in the nav: how visitors' browsers get the
    # theme's stylesheet (`SiteSetting#stylesheet_mode`, `ThemeCss::MODES`),
    # as a radiogroup of three choice tiles (`Admin::Ui::ChoiceTileComponent`)
    # named by the legend "Theme stylesheet", a field of the one Settings form
    # saved with its save bar (which names it by the legend). Design System
    # StudioSettings, "a tenth section, Page speed", whose keys,
    # `settings_screen.page_speed.*`, name this class (the other cards are
    # `*CardComponent`).
    #
    # - `stylesheet` is the built stylesheet the site serves now
    #   (`Theme::Stylesheet.current`, nil before a build): the size line above
    #   the tiles says its compressed size and what Automatic does with it,
    #   whatever is chosen, since it explains Automatic. KB of 1,024 bytes,
    #   one decimal (`ThemeCss.kilobytes`).
    # - The CDN help under the tiles says what a CDN's Early Hints do for a
    #   separate file; nothing here can tell whether a CDN sends them.
    #
    # No At a glance row: it is a choice, not a state that can go wrong.
    class PageSpeedComponent < Admin::AdminComponent
      FIELD_ID = "settings-stylesheet_mode".freeze

      # Where the error summary's link for the field lands: the first tile.
      def self.first_choice_id = "#{FIELD_ID}-#{ThemeCss::MODES.first}"

      def initialize(values:, stylesheet:, errors: [])
        @values = values
        @stylesheet = stylesheet
        @errors = errors
      end

      def legend_id = "#{FIELD_ID}-legend"

      def size_id = "#{FIELD_ID}-size"

      def help_id = "#{FIELD_ID}-help"

      def errors_id = "#{FIELD_ID}-errors"

      private

      attr_reader :values, :stylesheet, :errors

      def choices
        ThemeCss::MODES.map do |mode|
          { value: mode, id: "#{FIELD_ID}-#{mode}", title: t(".choices.#{mode}.label"), line: t(".choices.#{mode}.help"), checked: mode == values.stylesheet_mode }
        end
      end

      # What Automatic does with the stylesheet served now: drawn in only
      # when its size allows and a `<style>` would not change it, as the
      # public layout decides.
      def size_line
        return t(".size.unknown") unless stylesheet

        size = ThemeCss.kilobytes(stylesheet.compressed_size)
        stylesheet.inline?("automatic") ? t(".size.inline", size: size) : t(".size.file", size: size)
      end
    end
  end
end
