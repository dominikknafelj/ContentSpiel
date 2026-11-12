module Admin
  # Generate… and Regenerate… on Your account's Recovery codes card
  # (`Admin::AccountScreen::RecoveryCardComponent`): a new set of the
  # signed-in person's own codes (`RecoveryCodes::Generate`, which deletes
  # every code they held), behind Confirm it's you.
  #
  # The answer is a stream: the card drawn again, and the codes shown once
  # (`AccountRecoveryCodes`), on a page Turbo keeps no snapshot of. The codes
  # reach no log line, event or attribute.
  class RecoveryCodesController < BaseController
    include RecentConfirmation

    require_recent_confirmation only: :create

    def create
      result = RecoveryCodes::Generate.call(Current.user)
      return forbidden! unless result.ok?

      render turbo_stream: [
        turbo_stream.replace(AccountScreen::RecoveryCardComponent::ID, AccountScreen::RecoveryCardComponent.for(Current.user, url_options: admin_url_options)),
        *AccountRecoveryCodes.streams(turbo_stream, result.record)
      ]
    end
  end
end
