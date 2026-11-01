module BlockTypes
  # A card: an icon the theme declares, a title, a plain-text text and a link
  # (theme choices spec, "The Card block").
  #
  # WHERE EACH VALUE LIVES. The icon and the link are the same in every
  # language and are settings; the title and the text are translated schema
  # fields (`translated_settings`). So no column, no migration and no
  # service. Nothing is required: the picker makes an empty card first, and
  # the public component draws nothing until it has a title or a text.
  #
  # THE ICON is a name from the theme's `icons` list (`:theme_choice`): a
  # name the theme does not declare is drawn as no icon and left as stored
  # (the stored-name rule). THE LINK is a `:link`; the component draws it
  # only while `ContentModel::FieldTypes.link?` accepts the stored value.
  module Card
    def self.register
      BlockTypes.register :card do |t|
        t.label "Card"
        t.icon "card"
        t.field :icon, :theme_choice, of: :icons
        t.field :title, :string, translated: true
        t.field :text, :text, translated: true
        t.field :link, :link
        t.component Blocks::CardComponent
        t.theme_methods :block, :page, :title, :text, :link, :icon, :icon_name
        t.summary ->(block, locale:) { Card.summary(block, locale: locale) }
        t.tokens themed: %w[card-ground card-line card-icon]
        t.stylesheet "card.css"
        # The icon is left out until the default theme declares one (the
        # choices theme's tests draw one); the link is a site address, which
        # every theme draws.
        t.sample settings: { "link" => "/about" },
                 translations: { "en" => { title: "Card title en", text: "Card text en" },
                                 "de" => { title: "Card title de", text: "Card text de" },
                                 "es" => { title: "Card title es", text: "Card text es" } },
                 shows: [ "Card title en", "Card text en" ]
      end
    end

    # The tile's line: the icon's label (in the language of CS Studio's
    # listing, as the theme labels it), " · " and the title, or Empty.
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      title = settings&.title.to_s.strip.truncate(SUMMARY_LENGTH)
      icon = Theme.current.choice(:icons, settings&.icon)&.label_for(locale) if settings&.icon.present?
      return [ [ :hint, :empty ] ] if title.empty? && icon.blank?

      [ ([ :text, "#{icon} · " ] if icon.present? && title.present?), [ :text, title.presence || icon ] ].compact
    end

    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH
  end
end
