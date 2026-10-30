module Admin
  # The mail login's own save (`PATCH /<admin>/settings/mail_login`) and
  # remove (`DELETE`), the instant actions of the Settings screen's Mail card
  # (spec "Settings → Mail", design answer M2). Built as
  # `Admin::AiKeysController` is, which says at length why: the login is
  # never a field of the Settings form (it is never rendered, so it can't be
  # a pending change), each action is its own form beside it, and the answer
  # is Turbo Streams that replace ONLY the login component and its forms
  # (plus the main form's base, the card's state and a toast), so whatever
  # the main form holds unsaved is left alone. The write, the carried base
  # (`main_base_updated_at`) and the answer's tail are `Admin::CarriedBase`'s,
  # shared with the AI key's controller.
  #
  # `settings.manage` only. `Settings::Save` is the writer: the permission
  # check, the encryption, "Set on", the audit event that says THAT the login
  # changed and never what it is, the refusal of a half the host sets, and
  # the sentence a site without encryption keys gets. A refusal is shown in
  # the login's slot with the entry open; a denial as the toast and the 403.
  class MailLoginsController < BaseController
    include CarriedBase

    before_action -> { require_permission("settings.manage") }

    # Username and password together; either may be left blank, not both. A
    # half the host sets is not posted (the card has no input for it).
    # `site_setting` is read only when it is the hash the form posts.
    def update
      posted = params[:site_setting]
      posted = posted.is_a?(ActionController::Parameters) ? posted.permit(*Settings::Save::MAIL_LOGIN).to_h : {}
      login = posted.transform_values { |value| value.to_s.strip }
      return answer(nil, error: t("admin.settings.mail_login.blank"), status: :unprocessable_entity) if login.values.all?(&:blank?)

      write(login, notice: t("admin.settings.mail_login.saved"))
    end

    # With no login stored there is nothing to remove: nothing is written and
    # nothing is announced. Only the halves the screen may write are cleared.
    def destroy
      return answer(nil) unless Current.site.mail_login_set?

      settings = MailSettings.current
      halves = Settings::Save::MAIL_LOGIN.reject { |column| settings.from_host?(Settings::Save::MAIL_ATTRIBUTES[column]) }
      write(halves.index_with { nil }, notice: t("admin.settings.mail_login.removed"))
    end

    private

    def write(attributes, notice:) = write_carrying_base(attributes, notice: notice)

    # `moved_to:` is the new base for the main form, nil to leave it alone.
    def answer(site, base: params[:main_base_updated_at].to_s, error: nil, moved_to: nil, notice: nil, status: :ok, toast: false)
      site ||= Current.site
      settings = MailSettings.current(site)
      forms_base = moved_to || base
      streams = [
        turbo_stream.replace(Admin::SettingsScreen::MailLoginComponent::ID,
          Admin::SettingsScreen::MailLoginComponent.new(site_setting: site, mail_settings: settings, error: (error unless toast))),
        turbo_stream.replace("settings-mail-login-forms", partial: "admin/settings/mail_login_forms", locals: { site_setting: site, main_base: forms_base }),
        # A new or removed login is a change of the delivery settings: a
        # verified site is untested again (`MailSettings`' fingerprint).
        turbo_stream.replace(Admin::SettingsScreen::MailStateComponent::ID, Admin::SettingsScreen::MailStateComponent.new(mail_settings: settings))
      ]
      respond_with_streams(streams, anchor: "mail", moved_to: moved_to, notice: notice, error: error, toast: toast, status: status)
    end
  end
end
