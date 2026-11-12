module Admin
  # The gate before a change to how a person signs in (adding a passkey, its
  # registration options, removing one, making recovery codes): the session
  # must have proved its person within Session::CONFIRM_WINDOW, by its
  # sign-in or by Confirm it's you (`ConfirmationsController`).
  #
  # `require_recent_confirmation(**before_action_options)` declares it. A
  # request outside the window writes nothing and is answered by its format:
  #
  # - JSON: 403 `{ "confirm": true }`, which `admin--passkeys--confirm#ensure`
  #   answers by opening the dialog before the call is made again;
  # - a Turbo Stream: 403 with a stream that appends a `request` target of
  #   `admin--passkeys--confirm` to the dialog's requests
  #   (`ConfirmIdentityDialogComponent::REQUESTS_ID`): the script opens the
  #   dialog and, once confirmed, sends again the form this answer refused
  #   (`data-confirm-identity`), which it knows by CONFIRM_HEADER;
  # - anything else: a 303 to Your account's passkeys, where the dialog
  #   stands (a 303, so a refused DELETE lands there as a GET).
  #
  # Both 403s carry CONFIRM_HEADER, so the script tells the gate's refusal
  # from any other 403 without reading the body.
  #
  # Renaming a passkey and ending a session are not gated: neither changes
  # how anyone signs in.
  module RecentConfirmation
    extend ActiveSupport::Concern

    CONFIRM_HEADER = "X-Confirm-Identity".freeze

    class_methods do
      def require_recent_confirmation(**before_action_options)
        before_action :refuse_without_recent_confirmation, **before_action_options
      end
    end

    private

    def refuse_without_recent_confirmation
      return if Current.session&.confirmed_recently?

      response.set_header(CONFIRM_HEADER, "required") if request.format.json? || request.format.turbo_stream?
      if request.format.json?
        render json: { confirm: true }, status: :forbidden
      elsif request.format.turbo_stream?
        request_target = helpers.tag.div(data: { "admin--passkeys--confirm-target": "request" })
        render turbo_stream: turbo_stream.append(Admin::Ui::ConfirmIdentityDialogComponent::REQUESTS_ID, request_target), status: :forbidden
      else
        redirect_to admin_account_path(**admin_url_options, anchor: "passkeys"), status: :see_other
      end
    end
  end
end
