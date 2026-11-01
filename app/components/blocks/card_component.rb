module Blocks
  # The Card block on the public site (`BlockTypes::Card`). It reads the
  # block it is handed -- a published view on the site, the rows in a
  # preview -- and nothing else. A theme may replace its template and call
  # only what the type's `theme_methods` names: `title`, `text`, `link`,
  # `icon`, `icon_name`, `image`.
  #
  # A CARD IS DRAWN WITH A TITLE, A TEXT OR AN IMAGE, in the visitor's language
  # with the site's fallback; an icon or a link alone draws nothing. The text
  # is plain text (the template prints it escaped), the icon is decoration.
  class CardComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = title.present? || text.present? || image.present?

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

    # What a template hands to the one picture every image is drawn with, or
    # nil for no image (none chosen, a file that is gone):
    # `render Media::PictureComponent.new(**image, css_class: "…")`. A Hash of
    # that component's own keywords rather than three more methods, because
    # the three only mean anything together and a template tests the one
    # value (`if image`); `image[:asset]` is the Image block's `asset`.
    #
    # `alt` is as the Image block's: the override goes in whole so that one
    # written in another language never beats the library's in this one
    # (`Blocks::ImageComponent#alt`). It may be "" for an image that is
    # decoration beside the card's words. It is never blank for an image that
    # is the card's only link, whose alt is the link's name: there the library
    # image's title stands in, so the public link always has a name, and the
    # tile tells the editor (`BlockTypes::Card.unnamed_image_link?`).
    def image
      return @image if defined?(@image)

      asset = block.media_asset
      @image = if asset&.file&.attached?
        alt = asset.alt_text(override: block.read_attribute(:alt))
        alt = asset.title.to_s if alt.to_s.strip.empty? && link && !title && !text
        { asset: asset, alt: alt, sizes: Blocks::ImageComponent.sizes_for(block) }.freeze
      end
    end
  end
end
