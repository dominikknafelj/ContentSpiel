require "test_helper"

# The `Admin::Media` trap (`test/lib/admin_media_namespace_test.rb`), for
# the translation helpers: an `Admin::Translations` module -- the obvious
# name for the Translations screen's components, which live under
# `Admin::TranslationScreen` instead -- would shadow the top-level
# `Translations` module (`Translations::Status`, `::Tracker`, `::Confirm`)
# for every bare `Translations::` reference lexically nested under
# `module Admin` (`Admin::TranslationsController` has several), and an
# `Admin::AI` (or `Admin::Ai`, which is what Zeitwerk would make of an
# `admin/ai/` directory without the `ai` -> `AI` inflection) would do the
# same to `AI.configured?`/`AI::Translate`.
module Admin
  module TranslationNamespaceProbe
    def self.resolve_status = Translations::Status
    def self.resolve_translate = AI::Translate
  end
end

class AdminTranslationNamespaceTest < ActiveSupport::TestCase
  setup { Rails.application.eager_load! }

  test "nothing defines Admin::Translations, Admin::AI or Admin::Ai" do
    %i[Translations AI Ai].each do |name|
      assert_not Admin.const_defined?(name, false),
        "Admin::#{name} exists, which would shadow a top-level namespace for every bare reference " \
          "lexically nested under module Admin -- admin components go under Admin::TranslationScreen"
    end
  end

  test "bare Translations:: and AI:: references lexically nested under Admin still resolve to the top level" do
    assert_equal ::Translations::Status, Admin::TranslationNamespaceProbe.resolve_status
    assert_equal ::AI::Translate, Admin::TranslationNamespaceProbe.resolve_translate
  end
end
