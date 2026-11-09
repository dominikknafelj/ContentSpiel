module Admin
  module SettingsScreen
    # The API key's part of the AI card: AiState's chip with Replace and
    # Remove… (Add key when there is none). The chip reads "Key saved", then
    # "added 2 Oct" when the key has a date; "No key" with a provider and no
    # key; and "Off" without a provider, whether a key is stored or not.
    # Replace/Add key swaps the chip for a password input with Save key and
    # Cancel -- client side, `admin--settings--ai`. Replace, Add key and Save
    # key are secondary, Remove… the danger text and Cancel the tertiary: an
    # instant action is never the primary, which is the save bar's Save.
    #
    # NO PART OF THE KEY IS EVER RENDERED, and nothing here decrypts it: only
    # `SiteSetting#ai_api_key_set?` (the raw column) and the saved-on date are
    # read, so a stored key the current encryption keys can't read still shows
    # as set and can be replaced or removed. The input is never pre-filled.
    #
    # The component sits INSIDE the Settings form (it is part of the card) but
    # none of its controls belongs to that form: the input and Save key reach
    # the key's own form (`settings-ai-key-form`, a sibling after the main
    # form) through `form=`, so the footer never counts them and Save never
    # sends them; Replace, Remove… and Cancel are unnamed buttons. Replace /
    # Add key, Remove…, the input and Save key are `admin--saving--pending-lock`
    # controls: they wait while the main form has unsaved changes.
    #
    # The root's id is what a Turbo Stream `replace` of a key save targets.
    # `error:` is a refusal (a blank key) shown in the slot, with the input open.
    class AiKeyComponent < Admin::AdminComponent
      ID = "settings-ai-key".freeze
      KEY_FORM = "settings-ai-key-form".freeze
      REMOVE_DIALOG = "settings-ai-remove-key-dialog".freeze
      LOCK = { "admin--saving--pending-lock-target": "control" }.freeze

      def initialize(site_setting:, error: nil)
        @site_setting = site_setting
        @error = error
      end

      def key_set? = site_setting.ai_api_key_set?

      def editing? = error.present?

      # "added 2 Oct", or "added 2 Oct 2025" when the year isn't this one (in
      # the site zone, which `Admin::BaseController` has put on `Time.zone`);
      # nil when the key has no date.
      def added_label
        date = site_setting.ai_api_key_saved_on
        return nil unless date

        t(".added", date: I18n.l(date, format: date.year == Time.zone.today.year ? :"admin.short" : :"admin.short_with_year"))
      end

      # The date follows Key saved only: under Off, a key kept while no
      # provider is chosen, it would read as the day AI translation was
      # turned off.
      def chip
        state = AiState.of(site_setting)
        Admin::Ui::StateChipComponent.new(tone: AiState.tone(state), label: AiState.word(state), detail: (added_label if state == :key_saved),
          data: { ai_key_state: key_set? ? "set" : "unset" })
      end

      private

      attr_reader :site_setting, :error
    end
  end
end
