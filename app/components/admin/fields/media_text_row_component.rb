module Admin
  module Fields
    # One image's row of a Gallery block's card (`MediaTextsField`, spec
    # §10.3, StudioGallery D3): the drag handle, the thumbnail, the image's
    # Caption and Alt text in the language drawn, and Remove. Drawn once per
    # image by the server, and once more, blank, inside the rows'
    # `<template>` (`template: true`), which `admin--editor--gallery` copies
    # for an image the picker hands it: every `__ID__` in a name or an id is
    # the image's id, and the script fills in the thumbnail, the names of
    # the handle and of Remove, and the placeholders.
    #
    # `list:` false is a row of a translation tab: no handle and no Remove
    # (the list is changed in the default language), and each field has the
    # default language's text above it (`reference:`, `language:`).
    #
    # A MISSING IMAGE (an id whose image is trashed, purged or has lost its
    # file) draws no fields: its texts ride along in hidden inputs, so a
    # save of the gallery keeps them for the day the image is restored.
    class MediaTextRowComponent < AdminComponent
      WORDS = "admin.components.fields.media_texts".freeze
      TEMPLATE_ID = "__ID__".freeze

      def initialize(id:, asset:, texts:, input_name:, input_id:, locale:, list: true, reference: {}, language: nil, template: false)
        @id = template ? TEMPLATE_ID : id.to_s
        @asset = asset
        @texts = texts.to_h
        @input_name = input_name
        @input_id = input_id
        @locale = locale
        @list = list
        @reference = reference.to_h
        @language = language
        @template = template
      end

      def list? = @list

      def template? = @template

      def missing? = !template? && asset.nil?

      def title = asset&.title.to_s

      def name_for(part) = "#{input_name}[#{id}][#{part}]"

      def id_for(part) = "#{input_id}-#{id}-#{part}"

      def caption = texts["caption"]

      def alt = texts["alt"]

      def library_alt = template? ? "" : Admin::Columns::MediaColumnComponent.default_alt(asset, locale)

      def library_caption = template? ? "" : Admin::Columns::MediaColumnComponent.default_caption(asset, locale).to_s

      def alt_placeholder = library_alt.presence || words(:no_library_alt)

      # The well's bottom edge is the warn colour while it shows that the
      # library has no alt either (the media panel's `.admin-media-alt-warn`).
      def alt_class = class_names(helpers.setup_input_class, "admin-gallery-row__alt", "admin-gallery-row__alt--warn": library_alt.blank? && !template?)

      # Caption is one line that grows with what is typed.
      def caption_class = "#{helpers.setup_input_class} resize-none [field-sizing:content]"

      # "Use library caption": drawn where the library image has a caption,
      # shown while the gallery's own is blank (the script keeps that so as
      # the caption is typed in). The template draws it hidden, and the
      # script fills it for an image whose library caption it is handed.
      def offer_caption? = template? || library_caption.present?

      def offer_hidden? = template? || caption.present?

      def reference_text(part)
        text = reference[part]
        text.present? ? t("#{WORDS}.reference", language: language, text: text) : nil
      end

      def thumbnail_url = asset&.thumbnail_url

      def blurred? = Media::Asset.preview_url?(thumbnail_url)

      def words(key, **values) = t("#{WORDS}.#{key}", **values)

      def target(name) = { "admin--editor--gallery-target": name }

      def row_data = { **target("row"), asset_id: id, title: (title unless template?) }.compact

      def handle_data = { **target("handle"), action: "keydown->admin--editor--gallery#key focusout->admin--editor--gallery#blur" }

      def remove_data = { action: "admin--editor--gallery#remove" }

      def offer_data = { action: "admin--editor--gallery#useLibraryCaption", caption: library_caption }

      def caption_data = { action: "input->admin--editor--gallery#captionTyped" }

      # The row's frame, the card's paper tile, and its four columns (a
      # translation tab's two: no handle, no Remove).
      def row_class = class_names("admin-gallery-row grid items-start gap-2.5 rounded-tile bg-paper p-2",
        list? ? "grid-cols-[20px_96px_minmax(0,1fr)_28px]" : "grid-cols-[96px_minmax(0,1fr)]")

      private

      attr_reader :id, :asset, :texts, :input_name, :input_id, :locale, :reference, :language
    end
  end
end
