module Admin
  # The Translations screen's type filter as the shared segmented control's
  # radios (`Admin::Ui::SegmentedComponent`): All, then one segment per type
  # the screen lists, each with how many rows it holds. `counts` is the
  # screen's per-type numbers, and All is their sum; `type` the chosen type,
  # blank for All. Its words are the screen's own (`admin.translations.index`).
  module TranslationsFilterHelper
    def translation_type_segments(types:, counts:, type:)
      scope = "admin.translations.index"
      all = [ "", t("#{scope}.all"), counts.values.sum ]
      [ all, *types.map { |name| [ name, t("#{scope}.types.#{name}"), counts.fetch(name) ] } ].map do |value, label, count|
        { label:, value:, count:, id: "translations-type-#{value.presence || "all"}", current: type.to_s == value }
      end
    end
  end
end
