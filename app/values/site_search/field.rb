module SiteSearch
  # One weighted text of a search document (spec §4.2): `name` is the field
  # (`NAMES`), `weight` its rank (`:a` the title and tags, `:b` the summary,
  # `:c` the body, `:d` the code). The text is plain and cut at
  # `SiteSearch::MAX_TEXT`, whoever builds the field, so no field can
  # overflow a backend's index inside the publish that writes it.
  Field = Data.define(:name, :weight, :text)

  class Field
    NAMES = %w[title summary tags body code].freeze
    WEIGHTS = %i[a b c d].freeze

    def initialize(name:, weight:, text:)
      raise ArgumentError, "a search field is one of #{NAMES.join(", ")}: #{name.inspect}" unless NAMES.include?(name)
      raise ArgumentError, "a search field's weight is one of #{WEIGHTS.map(&:inspect).join(", ")}: #{weight.inspect}" unless WEIGHTS.include?(weight)

      super(name: name, weight: weight, text: SiteSearch.cut(text.to_s))
    end
  end
end
