module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::MatrixComponent`: rows alternating outdated
    # and missing-only for the first posts of the development database (so it
    # may be empty there), then the empty card.
    class MatrixComponentPreview < ViewComponent::Preview
      Item = Admin::TranslationsController::Item

      def rows
        items = Post.kept.order(updated_at: :desc).limit(4).each_with_index.map do |post, index|
          states = index.even? ? { "de" => :outdated, "es" => :missing } : { "de" => :complete, "es" => :missing }
          Item.new(type: "post", record: post, states:)
        end
        render Admin::TranslationScreen::MatrixComponent.new(items:, locales: %w[de es])
      end

      def empty
        render Admin::TranslationScreen::MatrixComponent.new(items: [], locales: %w[de es])
      end
    end
  end
end
