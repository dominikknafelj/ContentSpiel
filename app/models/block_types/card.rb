module BlockTypes
  # A card: an image from the library, an icon the theme declares, a title, a
  # plain-text text and a link (theme choices spec, "The Card block"; the image
  # is #144, `docs/superpowers/specs/2026-11-01-card-image-design.md`).
  #
  # WHERE EACH VALUE LIVES. The icon and the link are the same in every
  # language and are settings; the title and the text are translated schema
  # fields (`translated_settings`). So no column, no migration and no
  # service. Nothing is required: the picker makes an empty card first, and
  # the public component draws nothing until it has a title, a text or an
  # image.
  #
  # THE IMAGE is the Image block's own two columns, `media_asset_id` and the
  # translated `alt` override (`uses`), so `Media::Choosing`, the usages, the
  # published copy, the trash and the foreign key treat it as they treat that
  # block's: nothing asks a type's name. It is optional where the Image
  # block's is the block's whole point, which is why the tile marks no card
  # for having none (`Admin::EditorScreen::TileSummaryComponent#missing_image?`:
  # a type with a `summary` of its own says what it lacks).
  #
  # THE ICON is a name from the theme's `icons` list (`:theme_choice`): a
  # name the theme does not declare is drawn as no icon and left as stored
  # (the stored-name rule). THE LINK is a `:link`, an address or a reference to a
  # page or post; the component draws what `PublicSite::Urls#link_for` makes of it.
  module Card
    def self.register
      BlockTypes.register :card do |t|
        t.label "Card"
        t.icon "card"
        t.uses :image, :alt
        t.field :icon, :theme_choice, of: :icons
        t.field :title, :string, translated: true
        t.field :text, :text, translated: true
        t.field :link, :link
        t.component Blocks::CardComponent
        t.theme_methods :block, :page, :title, :text, :link, :icon, :icon_name, :image
        t.summary ->(block, locale:) { Card.summary(block, locale: locale) }
        t.tokens themed: %w[card-ground card-line card-icon]
        t.stylesheet "card.css"
        # The icon is one of the default theme's; the link is a site address,
        # which every theme draws.
        t.sample image: true, settings: { "icon" => "star", "link" => "/about" },
                 translations: { "en" => { title: "Card title en", text: "Card text en", alt: "Card alt en" },
                                 "de" => { title: "Card title de", text: "Card text de", alt: "Card alt de" },
                                 "es" => { title: "Card title es", text: "Card text es", alt: "Card alt es" } },
                 shows: [ "Card title en", "Card text en", %(alt="Card alt en") ]
      end
    end

    # The tile's line: the icon's label (in the language of CS Studio's
    # listing, as the theme labels it), " · " and the title; with no words of
    # those the image's library title (the tile draws its thumbnail beside
    # it), or Empty. An image that is the card's only link and has no alt says
    # that first (`unnamed_image_link?`).
    def self.summary(block, locale:)
      return [ [ :hint, :image_link_without_alt ] ] if unnamed_image_link?(block, locale: locale)

      settings = block.settings_object(locale: locale)
      title = settings&.title.to_s.strip.truncate(SUMMARY_LENGTH)
      icon = Theme.current.choice(:icons, settings&.icon)&.label_for(locale) if settings&.icon.present?
      if title.empty? && icon.blank?
        image = block.media_asset&.title.to_s.strip.truncate(SUMMARY_LENGTH)
        return image.empty? ? [ [ :hint, :empty ] ] : [ [ :text, image ] ]
      end

      [ ([ :text, "#{icon} · " ] if icon.present? && title.present?), [ :text, title.presence || icon ] ].compact
    end

    # The default template puts the link on the image only when the language
    # shown has no title and no text, read with the site's fallback as the
    # public component reads them, or the tile would warn of a link that has
    # the fallback's words. Then the image's alt is the link's name, and a blank
    # one is said here to the editor, while a visitor gets the library's title
    # in its place (`Blocks::CardComponent#image`): a file's name is a poor name
    # for a link, and better than none.
    def self.unnamed_image_link?(block, locale:)
      asset = block.media_asset
      return false unless asset&.file&.attached?

      settings = block.settings_object(locale: locale, fallback: true)
      ContentModel::FieldTypes.link_value?(settings&.link) && settings.title.to_s.strip.empty? && settings.text.to_s.strip.empty? &&
        asset.alt_text(override: block.read_attribute(:alt), locale: locale).to_s.strip.empty?
    end

    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH
  end
end
