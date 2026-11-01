class Theme
  # One entry of a list a theme declares in theme.yml (`Theme::Declarations`).
  # `labels` maps a locale code to its words; `fields` are the page fields a
  # page template draws (always an Array, empty for the other lists); `file`
  # is an icon's file under the theme's assets/images, or nil; `from` says
  # whose entry it is: `:default` for an icon that names one of the default
  # theme's and brings no file (the file is the default's), `:theme` otherwise.
  Choice = Data.define(:list, :name, :labels, :fields, :file, :from) do
    # The words in `locale` (CS Studio's interface language), then English,
    # then whatever was given first. Always a String, to be escaped as text.
    def label_for(locale)
      labels[locale.to_s] || labels["en"] || labels.values.first
    end
  end
end
