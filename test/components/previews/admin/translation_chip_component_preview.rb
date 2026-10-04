module Admin
  # `Admin::TranslationChipComponent` (design pass spec §4): one example per
  # translation state.
  class TranslationChipComponentPreview < ViewComponent::Preview
    def complete
      render Admin::TranslationChipComponent.new(state: :complete, locale: "de")
    end

    def missing
      render Admin::TranslationChipComponent.new(state: :missing, locale: "de")
    end

    def outdated
      render Admin::TranslationChipComponent.new(state: :outdated, locale: "de")
    end
  end
end
