module BlockTypes
  # A list of library images drawn as a grid or a carousel (gallery block
  # spec). WHERE EACH VALUE LIVES: the layout, the frame's shape, whether an
  # image is shown whole and the list of images are the same in every
  # language and are settings; the gallery's name for a screen reader and
  # each image's caption and alt override are translated settings
  # (`translated_settings`). So no column, no migration and no service, as
  # for the Code block.
  #
  # THE IMAGES ARE REFERENCES. `images` is a `:media_list`: library image
  # ids in their order, which the save checks as it checks a hero's image
  # (`Media::Choosing#media_fields_choice_result`) and the usage index counts
  # (`Media::UsageIndex`, role `block_field`). An id that names no image
  # (written around the services, or an image gone since) is skipped
  # wherever the gallery is drawn or read: nothing here assumes every id
  # exists. `texts` is keyed by the image's id, so a reorder moves no text.
  #
  # Nothing is required: the picker makes an empty Gallery first, and the
  # public component draws nothing until there is an image.
  #
  # The name `gallery` is no constant of the application and must not become
  # one: a top-level `Gallery` would refuse a gem owner of that name at boot
  # (`TopLevelNames.owners`), so the type's helpers are this module's.
  module Gallery
    MAX_IMAGES = 60
    LABEL_LENGTH = 80
    TEXT_LENGTH = 1000
    # The most images the carousel draws a dot for; above it, the position
    # alone says where the visitor is.
    PICKER_MAX = 12
    LAYOUTS = { "grid" => "Grid", "carousel" => "Carousel" }.freeze
    DEFAULT_LAYOUT = "grid"
    RATIOS = { "3:2" => "3:2", "4:3" => "4:3", "1:1" => "Square", "16:9" => "16:9" }.freeze
    DEFAULT_RATIO = "3:2"

    def self.register
      BlockTypes.register :gallery do |t|
        t.label "Gallery"
        t.icon "images", family: :media
        t.field :layout, :select, options: LAYOUTS, default: DEFAULT_LAYOUT, control: :segmented
        t.field :ratio, :select, options: RATIOS, default: DEFAULT_RATIO, label: "Shape"
        t.field :fit, :boolean, label: "Show whole images"
        t.field :label, :string, translated: true, max: LABEL_LENGTH, help: :"gallery.label_help", placeholder_public: "blocks.gallery.label"
        t.field :images, :media_list, max: MAX_IMAGES
        t.field :texts, :media_texts, translated: true, of: :images, max: TEXT_LENGTH
        t.component Blocks::GalleryComponent
        t.theme_methods :block, :page, :layout, :ratio, :fit, :label, :items, :sizes, :string, :pattern
        t.stylesheet "gallery.css"
        t.summary ->(block, locale:) { Gallery.summary(block, locale: locale) }
        t.preview ->(block, locale:) { Gallery.preview(block, locale: locale) }
        t.search_text ->(block, locale:) { Gallery.search_text(block, locale: locale) }
        # Three images, so a carousel visibly steps, its texts written by
        # position (`ContentModel::SampleBlock` re-keys them to the ids): the
        # first image has a caption and an alt override, the second a caption
        # only, and the third neither, so it takes the library's. `fit` is
        # written out, false, so the canary compares it with the rows.
        t.sample images: 3, settings: { "layout" => "carousel", "ratio" => "4:3", "fit" => false },
                 translations: %w[en de es].to_h { |locale|
                   [ locale, { label: "Harbour #{locale}",
                               texts: { "1" => { "caption" => "Gallery caption #{locale}", "alt" => "Gallery alt #{locale}" },
                                        "2" => { "caption" => "Second caption #{locale}" } } } ]
                 },
                 shows: [ "Gallery caption en", %(alt="Gallery alt en"), %(aria-label="Harbour en") ]
      end
    end

    def self.layout_of(value) = LAYOUTS.key?(value.to_s) ? value.to_s : DEFAULT_LAYOUT

    # The tile's line of a closed Gallery, as parts (spec §10.5): the
    # layout's word with the number of images in the list ("Carousel · 12
    # images"), or "Empty" with none; then, when some image a visitor in this
    # language is given no alt for, the warn badge "3 without alt". The alt
    # counted is the one the site draws: `Media::Asset#alt_text` handed the
    # block's overrides of every language (`{ locale => alt }`), so it walks
    # the fallback chain over the override and the library's alt together,
    # as the Card's tile asks it. An id that names no image, or an image
    # whose file is gone, is in the line's count and not in the badge's,
    # since the site skips it.
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      ids = Array(settings&.images)
      return [ [ :word, :empty ] ] if ids.empty?

      line = [ :word, layout_of(settings.layout).to_sym, { count: ids.size } ]
      translations = block.translated_settings.to_h
      # `joins`, not `with_file`'s preload: the same images with a file, in
      # one query, since the summary needs no blob.
      without = Media::Asset.kept.joins(:file_attachment).where(id: ids).count do |asset|
        overrides = translations.transform_values { |values| values.to_h.dig("texts", asset.id.to_s, "alt") }.compact
        asset.alt_text(override: overrides, locale: locale).strip.empty?
      end
      without.positive? ? [ line, [ :warn, :without_alt, { count: without } ] ] : [ line ]
    end

    # The tile's preview: the label as the heading when one is written in
    # this language, over the summary line, so the tile reads "Gallery ·
    # Harbour walk"; with none, the tile keeps its line alone.
    def self.preview(block, locale:)
      label = block.settings_object(locale: locale)&.label
      ContentModel::Preview.new(heading: label, line: true) if label.present?
    end

    # The captions and alt overrides of the images that are there, in the
    # list's order, read as the public page reads them (the fallback-aware
    # reader), as the Image block gives its own caption and alt. The library
    # image's own alt and caption are the asset's, read live and in no copy,
    # so they would drift with every library edit and are not searched
    # (`BlockTypes::Image.search_text`). The label is a screen reader's name
    # of the gallery, not words on the page.
    def self.search_text(block, locale:)
      settings = block.settings_object(locale: locale, fallback: true)
      ids = Array(settings&.images)
      return [] if ids.empty?

      there = Media::Asset.with_file.where(id: ids).select { |asset| asset.file.attached? }.to_set(&:id)
      texts = settings.texts.to_h
      ids.select { |id| there.include?(id) }.flat_map { |id| texts.fetch(id.to_s, {}).values_at("caption", "alt") }.compact
    end
  end
end
