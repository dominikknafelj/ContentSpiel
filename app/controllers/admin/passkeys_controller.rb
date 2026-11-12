module Admin
  # The Passkeys card's actions on Your account
  # (`Admin::AccountScreen::PasskeysCardComponent`), on the signed-in
  # person's own passkeys only: a passkey is looked up among
  # `Current.user.passkeys`, so another person's id is a 404.
  #
  # Three are behind Confirm it's you (`Admin::RecentConfirmation`): the
  # registration options, the add and the remove change how the person signs
  # in. A rename does not.
  #
  # ADDING is two requests from `admin--passkeys--register`:
  # - `options`, the registration options as JSON, with a challenge of the
  #   purpose "register" kept for `create`; the person's own credentials are
  #   excluded, so an authenticator that holds one already says so;
  # - `create`, the browser's credential (`params[:credential]`, JSON) and the
  #   typed name. A success is a stream that redraws both cards and Confirm
  #   it's you (which now offers the passkey), says "Passkey added." and,
  #   when `Passkeys::Add` made codes (the person held no unused one), shows
  #   them once on a page Turbo keeps no snapshot of. A refusal is 422
  #   `{ "error" }`, the sentence the dialog shows.
  #
  # FROM THE ENROLMENT PAGE (`from: "enrolment"`), the answer goes on to
  # where the person was going (`after_authentication_url`): with codes, a
  # stream that replaces the page's `#enrolment` with them, Done leading
  # there (the page carries `turbo-cache-control: no-cache` itself); with
  # none (the person still held unused ones), a 303 there, which the script
  # follows. The codes are drawn in this answer alone, never kept in the
  # flash or the session.
  #
  # Nothing of the ceremony reaches a page, a span or the log: the challenge
  # is in its own encrypted cookie (`PasskeyChallenges`), the credential is
  # filtered from the log (`filter_parameters`), and the answer holds
  # neither.
  class PasskeysController < BaseController
    include MailLinkOrigin
    include PasskeyChallenges
    include RecentConfirmation

    # Enrolment's own add (`Admin::PasskeyEnrolment`).
    skip_before_action :require_passkey_enrolment, only: %i[ options create ]
    require_recent_confirmation only: %i[ options create destroy ]
    before_action :require_passkey_relying_party, only: %i[ options create ]
    before_action :set_passkey, only: %i[ update destroy ]

    def options
      user = Current.user
      options, challenge = registration.options(user_handle: user.webauthn_handle!, user_name: user.email_address,
        display_name: user.name.presence || user.email_address, exclude: user.passkeys.pluck(:external_id))
      issue_passkey_challenge("register", challenge)
      render json: options
    end

    # The challenge is taken before anything is decided, so a refused answer
    # spends it too.
    def create
      challenge = take_passkey_challenge("register")
      result = Passkeys::Add.call(Current.user, registration: registration.verify(params[:credential], challenge: challenge),
        name: params[:name], **mail_link_origin)
      return render(json: { error: result.errors.first }, status: :unprocessable_entity) unless result.ok?

      _passkey, codes = result.record
      return enrolment_answer(codes) if params[:from] == "enrolment"

      # `addable: true`: this action answers only where a relying party is.
      streams = [
        turbo_stream.replace(AccountScreen::PasskeysCardComponent::ID, AccountScreen::PasskeysCardComponent.for(Current.user, addable: true, url_options: admin_url_options)),
        turbo_stream.replace(AccountScreen::RecoveryCardComponent::ID, AccountScreen::RecoveryCardComponent.for(Current.user, url_options: admin_url_options)),
        turbo_stream.replace(Ui::ConfirmIdentityDialogComponent::ID, Ui::ConfirmIdentityDialogComponent.new(passkey: true, url_options: admin_url_options)),
        Admin::ToastStream.for(turbo_stream, t("admin.accounts.passkeys.added"))
      ]
      streams.concat(AccountRecoveryCodes.streams(turbo_stream, codes)) if codes
      render turbo_stream: streams
    end

    # A refusal redraws the dialog's fields with what was typed and the
    # sentence, and leaves the dialog open; a success redraws the card,
    # which closes it, and hands the focus back to the passkey's Rename.
    def update
      result = Passkeys::Rename.call(@passkey, name: params[:name])
      if result.ok?
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace(AccountScreen::PasskeysCardComponent::ID,
                AccountScreen::PasskeysCardComponent.for(Current.user, addable: passkey_relying_party.present?, url_options: admin_url_options, autofocus: @passkey.id)),
              Admin::ToastStream.for(turbo_stream, t("admin.accounts.passkeys.renamed"))
            ]
          end
          format.html { redirect_to passkeys_card_path, status: :see_other, notice: t("admin.accounts.passkeys.renamed") }
        end
      else
        render turbo_stream: turbo_stream.replace(AccountScreen::PasskeyRenameFieldsComponent.id(@passkey),
          AccountScreen::PasskeyRenameFieldsComponent.new(passkey: @passkey, errors: result.errors, url_options: admin_url_options)),
          status: :unprocessable_entity
      end
    end

    # Back to the card, the whole screen drawn again: the passkey's row, the
    # count and, after the last one, the recovery codes all change. The last
    # passkey of a person the policy covers is refused whole
    # (`Passkeys::Remove`), whatever asked, and said in a toast in the
    # card's own words; any other refusal says its own sentence.
    def destroy
      result = Passkeys::Remove.call(@passkey)
      return redirect_to(passkeys_card_path, status: :see_other, notice: t("admin.accounts.passkeys.removed")) if result.ok?

      message = removal_refusal(result)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: Admin::ToastStream.for(turbo_stream, message, kind: :error), status: Admin::RefusalStatus.for(result) }
        format.html { redirect_to passkeys_card_path, status: :see_other, alert: message }
      end
    end

    private

    def enrolment_answer(codes)
      return redirect_to(after_authentication_url, status: :see_other) unless codes

      render turbo_stream: turbo_stream.replace(EnrolmentsController::ID,
        Ui::RecoveryCodesComponent.new(codes: codes, frame: :page, done_href: after_authentication_url, id: EnrolmentsController::ID))
    end

    def set_passkey
      @passkey = Current.user.passkeys.find(params[:id])
    end

    def removal_refusal(result)
      return t("admin.components.account_screen.passkeys_card.last_required") if result.errors == [ Passkeys::Remove.last_required ]

      result.errors.first
    end

    def registration = SignIn::PasskeyRegistration.new(relying_party: passkey_relying_party)

    def passkeys_card_path = admin_account_path(**admin_url_options, anchor: AccountScreen::PasskeysCardComponent::HEADING_ID)

    def require_passkey_relying_party
      head :not_found if passkey_relying_party.nil?
    end
  end
end
