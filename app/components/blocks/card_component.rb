module Blocks
  # The Card block on the public site (`BlockTypes::Card`). It reads the
  # block it is handed -- a published view on the site, the rows in a
  # preview -- and nothing else. A theme may replace its template and call
  # only what the type's `theme_methods` names: `title`, `text`, `link`,
  # `icon`, `icon_name`.
  #
  # A CARD IS DRAWN WITH A TITLE OR A TEXT, in the visitor's language with
  # the site's fallback; an icon or a link alone draws nothing. The text is
  # plain text (the template prints it escaped), the icon is decoration.
  class CardComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = title.present? || text.present?

    private

    attr_reader :block, :page

    def settings = @settings ||= block.settings_object(fallback: true)

    def title = settings&.title.to_s.strip.presence

    def text = settings&.text.to_s.strip.presence

    # The stored address while the rule accepts it, else nil: a value that
    # was accepted once and is refused now (the rule tightened, or a write
    # around the service) draws no link.
    def link
      value = settings&.link
      value if ContentModel::FieldTypes.link?(value)
    end

    # The stored icon's name while the theme declares it, else nil: the
    # name is a `Theme::Declarations` name, so it is safe as a class suffix.
    def icon_name
      name = settings&.icon.to_s.strip
      name if name.present? && Theme.current.choice(:icons, name)
    end

    # The theme's icon file as the theme wrote it, or nil for no icon, an
    # undeclared name and an icon file that is gone or no longer passes the
    # fence.
    def icon = icon_name && Theme.current.icon_svg(icon_name)
  end
end
