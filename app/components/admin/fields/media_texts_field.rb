module Admin
  module Fields
    # The captions and alt texts of a Gallery block's images
    # (`:media_texts`), drawn as the card's Images section (spec §10.2 and
    # §10.3, StudioGallery D2 and D3): the heading with "12 of 60", one row
    # per image of the list it describes (`MediaTextRowComponent`), in the
    # list's order, and under them Add images, Add a folder and the count.
    # The rows are the gallery's whole editor: the list itself is the hidden
    # input of the field `of:` names (`MediaListField`), which the rows'
    # script, `admin--editor--gallery`, writes and announces as `input`, so
    # the card's autosave sends the list and the texts together.
    #
    # THE LIST IS READ FROM `values:` (the FieldSet the block card draws),
    # never from a type's name: `of:` names the field, and its `max:` is the
    # limit. Without values (a caller that hands none) there is no list and
    # no row.
    #
    # On a translation tab the list is the default language's to change: the
    # heading says so, the rows have no handle and no Remove, nothing adds,
    # and each field has the default language's text above it (the
    # translation pair's reference drawn inline, so `reference?` is false).
    # Held by someone else, `HeldFields` makes the rows read-only and drops
    # every action of the script, which only writes.
    #
    # Adding needs `media.upload`, as choosing a hero's image does: without
    # it the picker is not on the page, so no add button is drawn, and
    # reordering and removing, which `ContentBlocks::Save` lets through
    # without it, stay. "Add a folder" is drawn only where the library has a
    # folder: one query per card.
    class MediaTextsField < Base
      WORDS = MediaTextRowComponent::WORDS

      # The words the script says or writes into a row it adds.
      SCRIPT_MESSAGES = %w[move remove picked_up moved dropped cancelled count count_line no_library_alt].map { |key| "components.fields.media_texts.#{key}" }.freeze

      def self.display(_field, _value) = nil

      def self.own_label?(_field) = true

      def self.reference?(_field) = false

      def list_field
        return @list_field if defined?(@list_field)

        @list_field = values&.definition&.fields&.find { |candidate| candidate.name == field.options[:of].to_s }
      end

      def ids = list_field ? Array(values.public_send(list_field.name)) : []

      def count = ids.size

      def max = list_field&.options&.[](:max)

      # The id `MediaListField` draws its input with: the rows are handed it.
      def list_input_id = "#{id_prefix}-#{field.options[:of]}"

      def translation_tab? = locale.to_s != ::Locales.default

      def list_editable? = list_field.present? && !translation_tab?

      def can_add? = list_editable? && can?("media.upload")

      def folders? = can_add? && Media::Folder.exists?

      def empty? = ids.empty?

      def full? = max.present? && count >= max

      def heading_id = "#{input_id}-heading"

      def limit_id = "#{input_id}-limit"

      def default_language = ::Locales.name(::Locales.default)

      # The images there are, by id: a kept image whose file is attached.
      # Anything else on the list is a missing image's row.
      def assets
        @assets ||= ids.empty? ? {} : Media::Asset.kept.with_file.where(id: ids).select { |asset| asset.file.attached? }.index_by(&:id)
      end

      def row(id) = row_component(id: id, asset: assets[id], texts: value.to_h.fetch(id.to_s, {}), reference: original.to_h.fetch(id.to_s, {}))

      def template_row = row_component(id: nil, asset: nil, texts: {}, template: true)

      def heading_count
        return t("#{WORDS}.translation_list", count: count, language: default_language) if translation_tab?

        max ? t("#{WORDS}.count", count: count, max: max) : nil
      end

      def count_line = max ? t("#{WORDS}.count_line", count: count, max: max) : nil

      def controller_data
        {
          controller: "admin--editor--gallery",
          action: "media-picker:picked->admin--editor--gallery#picked",
          "admin--editor--gallery-list-value": (list_input_id if list_editable?),
          "admin--editor--gallery-max-value": max,
          messages: messages_data(*SCRIPT_MESSAGES)
        }.compact
      end

      # Add images and Add a folder: the card's small secondaries, which at
      # the limit stay focusable with the limit line as their reason
      # (`aria-disabled`, `ButtonComponent`'s rule) and the script keeps so.
      def add_button(target, words, icon: nil)
        tag.button(type: "button", class: Admin::Ui::ButtonComponent.classes(:secondary, size: :small), "aria-haspopup": "dialog",
          "aria-disabled": (true if full?), "aria-describedby": (limit_id if full?),
          data: { "admin--editor--gallery-target": target, action: "admin--editor--gallery##{target}" }) do
          safe_join([ (helpers.render("admin/shared/icon", name: icon, size: "size-4") if icon), t("#{WORDS}.#{words}") ].compact)
        end
      end

      private

      def row_component(id:, asset:, texts:, reference: {}, template: false)
        MediaTextRowComponent.new(id: id, asset: asset, texts: texts, reference: reference, template: template, input_name: input_name, input_id: input_id,
          locale: locale, list: list_editable?, language: default_language)
      end
    end
  end
end
