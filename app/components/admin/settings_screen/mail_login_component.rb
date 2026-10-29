module Admin
  module SettingsScreen
    # The mail login's part of the Mail card (spec decision 2, design answer
    # M2), on the AI key's pattern (`AiKeyComponent`): written once, never
    # shown again. With no login stored, Username and Password are open with
    # "Save login"; once one is, a meta line "Set on 14 Oct 2026" with Replace
    # (which opens the two fields again, with Cancel) and Remove….
    #
    # NOTHING OF THE LOGIN IS EVER RENDERED and nothing here decrypts it: only
    # `SiteSetting#mail_login_set?` (the raw columns) and the saved-on date are
    # read, so a login the current encryption keys can't read still shows as
    # set and can be replaced or removed. The inputs are never pre-filled.
    #
    # A half the host's environment sets is a sunken box with "Set by the
    # host" and no input (its value is not shown either: it is a credential);
    # with both halves from the host there is nothing to save here at all.
    #
    # Like the key's, its controls sit inside the Settings form but belong to
    # the login's own form (`LOGIN_FORM`, after the main form) through
    # `form=`, so the footer never counts them; Replace, Remove…, the inputs
    # and Save login are `admin--saving--pending-lock` controls, the inputs
    # exempt while the entry is open (`admin--settings--mail`). `error:` is a
    # refusal shown in the slot, with the entry open.
    class MailLoginComponent < Admin::AdminComponent
      ID = "settings-mail-login".freeze
      LOGIN_FORM = "settings-mail-login-form".freeze
      REMOVE_DIALOG = "settings-mail-remove-login-dialog".freeze
      LOCK = { "admin--saving--pending-lock-target": "control" }.freeze
      FIELDS = { username: "mail_username", password: "mail_password" }.freeze

      def initialize(site_setting:, mail_settings:, error: nil)
        @site_setting = site_setting
        @mail_settings = mail_settings
        @error = error
      end

      def login_set? = site_setting.mail_login_set?

      # Which halves the screen may write: those the host doesn't set.
      def editable_fields = FIELDS.keys.reject { |field| mail_settings.from_host?(field) }

      def all_from_host? = editable_fields.empty?

      def entry_open? = error.present? || !login_set?

      def set_on
        at = site_setting.mail_login_saved_at
        return unless login_set? && at

        t(".set_on", date: I18n.l(at.in_time_zone(site_setting.effective_time_zone).to_date, format: :"admin.short_with_year"))
      end

      def input_id(field) = "settings-mail_#{field}"

      private

      attr_reader :site_setting, :mail_settings, :error
    end
  end
end
