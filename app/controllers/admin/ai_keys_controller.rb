module Admin
  # The AI API key's own save (`PATCH /<admin>/settings/ai_key`) and remove
  # (`DELETE`), the instant actions of the Settings screen's AI card (round 3,
  # Task 7; translation helpers spec §6.2). The key is deliberately not a field
  # of the Settings form -- it is never rendered, so it can't be a pending
  # change -- so each action is its own form beside it and answers with Turbo
  # Streams that replace ONLY the key component and its forms (plus the main
  # form's base and a toast): whatever the editor has typed into the main form
  # and not saved is left alone.
  #
  # `settings.manage` only: the Settings module also opens for `languages.manage`
  # alone, and this is not a languages action. `Settings::Save` is the writer
  # (it holds the permission check, the encryption, the saved-on date and the
  # audit event that says THAT the key changed and never what it is).
  #
  # THE CARRIED BASE, the write itself and the answer's tail are
  # `Admin::CarriedBase`'s, shared with the mail login's controller.
  class AiKeysController < BaseController
    include CarriedBase

    BLANK_KEY_MESSAGE = "Enter the API key first.".freeze

    before_action -> { require_permission("settings.manage") }

    # `site_setting` is read only when it is the hash the form posts: a forged
    # scalar (`site_setting=x`) has nothing to dig into and is a blank key, not
    # a 500.
    def update
      posted = params[:site_setting]
      key = (posted.is_a?(ActionController::Parameters) ? posted[:ai_api_key] : nil).to_s.strip
      return answer(nil, error: BLANK_KEY_MESSAGE, status: :unprocessable_entity) if key.blank?

      write({ "ai_api_key" => key }, notice: "API key saved")
    end

    # With no key stored there is nothing to remove: nothing is written and
    # nothing is announced (a second press, a stale tab).
    def destroy
      return answer(nil) unless Current.site.ai_api_key_set?

      write({ "ai_api_key" => nil }, notice: "API key removed")
    end

    private

    # The write, the carried-base rule and the answer's tail are
    # `Admin::CarriedBase`'s; this builds the key's own streams.
    def write(attributes, notice:) = write_carrying_base(attributes, notice: notice)

    # `moved_to:` is the new base for the main form, nil to leave it alone.
    def answer(site, base: params[:main_base_updated_at].to_s, error: nil, moved_to: nil, notice: nil, status: :ok, toast: false)
      site ||= Current.site
      forms_base = moved_to || base
      streams = [
        turbo_stream.replace(Admin::SettingsScreen::AiKeyComponent::ID, Admin::SettingsScreen::AiKeyComponent.new(site_setting: site, error: (error unless toast))),
        turbo_stream.replace("settings-ai-key-forms", partial: "admin/settings/ai_key_forms", locals: { site_setting: site, main_base: forms_base })
      ]
      # A successful key write makes a shown "CONNECTED · N MS" stale (it was
      # measured against the key just replaced or removed): back to the empty slot.
      streams << turbo_stream.replace(Admin::SettingsScreen::AiTestResultComponent::ID, Admin::SettingsScreen::AiTestResultComponent.new) if notice
      respond_with_streams(streams, anchor: "ai", moved_to: moved_to, notice: notice, error: error, toast: toast, status: status)
    end
  end
end
