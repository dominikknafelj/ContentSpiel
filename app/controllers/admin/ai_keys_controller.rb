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
  # THE CARRIED BASE. Each key write touches the settings row's `updated_at`,
  # and a main form left holding the old value would call its own next Save
  # stale. So the key forms carry the main form's base (`main_base_updated_at`)
  # and the answer moves the main form's `base_updated_at` forward ONLY when
  # this request wrote something AND the carried base was a parseable one that
  # was still current before the write -- the rule the editors use for a
  # block's answer. A key save from a stale tab must neither unlock its Save
  # nor cancel a 409 it was already shown; a press that wrote nothing moves
  # nothing; and a blank or unparseable carried base (a scripted client, a
  # damaged field) can't be shown to be current, so it moves nothing either.
  # When nothing moves, the forms are re-rendered carrying the value they were
  # given, unchanged, so the next press is judged the same way.
  class AiKeysController < BaseController
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

    def write(attributes, notice:)
      site = Current.site
      before = site.updated_at
      carried = params[:main_base_updated_at].to_s
      result = Settings::Save.call(site, attributes: attributes)
      site.reload

      if result.ok?
        moved = !base_older_than?(before, carried) && carried_parseable?(carried)
        answer(site, base: carried, moved_to: (site.updated_at.iso8601(6) if moved), notice: notice)
      else
        status = result.denied? ? :forbidden : :unprocessable_entity
        answer(site, base: carried, error: result.errors.to_sentence, status: status, toast: true)
      end
    end

    # `moved_to:` is the new base for the main form, nil to leave it alone.
    def answer(site, base: params[:main_base_updated_at].to_s, error: nil, moved_to: nil, notice: nil, status: :ok, toast: false)
      site ||= Current.site
      forms_base = moved_to || base
      streams = [
        turbo_stream.replace(Admin::SettingsScreen::AiKeyComponent::ID, Admin::SettingsScreen::AiKeyComponent.new(site_setting: site, error: (error unless toast))),
        turbo_stream.replace("settings-ai-key-forms", partial: "admin/settings/ai_key_forms", locals: { site_setting: site, main_base: forms_base })
      ]
      streams << turbo_stream.replace("settings-base-updated-at", partial: "admin/shared/base_updated_at_field",
        locals: { id: "settings-base-updated-at", value: moved_to }) if moved_to
      # A successful key write makes a shown "CONNECTED · N MS" stale (it was
      # measured against the key just replaced or removed): back to the empty slot.
      streams << turbo_stream.replace(Admin::SettingsScreen::AiTestResultComponent::ID, Admin::SettingsScreen::AiTestResultComponent.new) if notice
      streams << turbo_stream.append("toasts", Admin::ToastComponent.new(message: notice, kind: :success)) if notice
      streams << turbo_stream.append("toasts", Admin::ToastComponent.new(message: error, kind: :error)) if toast && error
      # Without Turbo (no JavaScript, a scripted client) a stream body would
      # be shown as text: the same outcome as a redirect to the card instead.
      # Decided by "does the client take a stream", not `respond_to`: the
      # write has happened, and a client that accepts neither must not be
      # answered 406 for it.
      if request.accepts.any? { |type| type.symbol == :turbo_stream }
        render turbo_stream: streams, status: status
      else
        flash[error ? :alert : :notice] = error || notice if error || notice
        redirect_to admin_settings_path(**admin_url_options, anchor: "ai"), status: :see_other
      end
    end

    # The same comparison the Settings form makes (`SettingsController#stale?`).
    def base_older_than?(updated_at, base)
      Time.iso8601(base) < updated_at
    rescue ArgumentError
      false
    end

    def carried_parseable?(base)
      Time.iso8601(base)
      true
    rescue ArgumentError
      false
    end
  end
end
