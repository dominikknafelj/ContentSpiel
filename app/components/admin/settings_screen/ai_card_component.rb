module Admin
  module SettingsScreen
    # The AI translation card (translation helpers spec §6.2; round 3, Task 7,
    # handoff §4.5). Provider and Model are pending fields of the one Settings
    # form like the other cards'; the key (`AiKeyComponent`) and Test
    # connection are instant actions of their own, associated with the forms in
    # `#settings-ai-key-forms` (rendered by `show` AFTER the main form --
    # forms can't nest) through `form=`.
    #
    # `admin--settings--ai` (this card's root) owns Replace/Cancel and gates
    # Test connection: it tests the SAVED settings, so it is disabled while
    # Provider or Model differ from `data-saved-value` ("Save provider and model
    # first. Tests the saved settings.") and, as every instant action is
    # while the main form has unsaved changes (decision D10), while anything is
    # pending ("Save or cancel your changes first."). The two can both apply --
    # a changed field is itself a pending change -- and then only the specific
    # one shows. `admin--saving--pending-lock` (same root) locks the key's controls and
    # carries the key row's own hint; Test connection is NOT one of its
    # controls, since its state is the union of both rules and is decided in
    # one place.
    class AiCardComponent < Admin::AdminComponent
      TEST_FORM = "settings-ai-test-form".freeze

      def initialize(site_setting:, values:, provider_errors: [], model_errors: [])
        @site_setting = site_setting
        @values = values
        @provider_errors = provider_errors
        @model_errors = model_errors
      end

      # Every registered provider, plus whatever is stored or typed even if it's
      # no longer registered (a removed plugin's), so a save resends that value
      # instead of the browser silently switching to the first option.
      def provider_names
        names = ::AI::Providers.names
        shown = values.ai_provider.presence
        shown && !names.include?(shown) ? [ shown, *names ] : names
      end

      def saved_provider = site_setting.ai_provider.to_s

      def saved_model = site_setting.ai_model.to_s

      private

      attr_reader :site_setting, :values, :provider_errors, :model_errors
    end
  end
end
