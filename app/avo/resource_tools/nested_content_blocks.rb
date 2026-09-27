# The content-block editor embedded in the Page form: one row per block, plus a
# permanently-present blank row to add the next one with.
#
# It is a resource tool rather than `field :content_blocks, as: :has_many,
# nested: true` because Avo 4.2.3's `nested:` option renders through
# Avo::Nested::FieldComponent, which lives in the paid `avo-nested` gem --
# Avo::Fields::Common::NestedFieldComponent#render? is literally
# `Avo.plugin_manager.installed?("avo-nested")`, so on this (Community)
# installation the option renders nothing at all. A resource tool over Rails'
# own `accepts_nested_attributes_for` is what Avo's own docs point Community
# users at, and it needs no JavaScript.
class Avo::ResourceTools::NestedContentBlocks < Avo::BaseResourceTool
  self.name = "Content blocks"

  # The per-locale accessors Mobility defines for a block's translated
  # attributes, e.g. [:caption_en, :caption_de, :caption_es].
  def locale_accessors(attribute)
    ::Locales.enabled.map do |locale|
      [ locale, ::Mobility.normalize_locale_accessor(attribute, locale).to_sym ]
    end
  end
end
