module Users
  # The invited person sets a password through the link (design answer M5):
  # the name and the password are written, `invited_at` is cleared, and from
  # then on the row is a user who can sign in. Signing them in is the
  # controller's (it holds the request).
  #
  # THE TOKEN IS THE CREDENTIAL. Whoever is signed in in this browser, if
  # anyone, is not who accepts: the actor is the user the token names, and
  # the event (`user.invite_accepted`) is theirs, as the reset flow passes
  # `actor: user` to `Users::UpdatePassword`. So there is no permission to
  # ask: a token that finds an invited row IS the right to finish that
  # account, and nothing else.
  #
  # THE ANSWERS (plan Ruling 3). A refusal of the link is a symbol in
  # `result.errors`, which the page turns into its own words:
  #   [:expired]  the token finds no row: lapsed, resent since (the old link),
  #               withdrawn (the row is gone) or never valid -- one answer, so
  #               the page does not say whether an invite existed (M5);
  #               `record` is nil.
  #   [:used]     the token finds a row that is no longer invited: accepting
  #               keeps `invite_sent_at`, so a used link still finds its row.
  #               `record` is that user (the page offers "Sign in").
  # Any other failure is the form's: `errors` are the model's sentences
  # (a blank, short or unconfirmed password; a name too long) and `record`
  # is the invited user, still invited.
  #
  # The row is locked and asked again before it is written, so a second press
  # that arrives while the first is in flight reads `:used`.
  class AcceptInvite < ApplicationService
    # authorize: none (the invite token is the credential: a token that finds an invited row is the right to finish that account, and the service acts as that user, as the reset flow does)
    include OwnerProtection

    EXPIRED = :expired
    USED = :used

    def initialize(token:, name:, password:, password_confirmation:)
      @token = token.to_s
      @name = name
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
    end

    def call
      @user = User.find_by_token_for(:invite, @token)
      return failure(nil, [ EXPIRED ]) if @user.nil?

      # From here on everything is recorded as the invited person's.
      @actor = @user
      return failure(@user, [ USED ]) unless @user.invited?
      return blank_password if @password.blank?
      return unconfirmed_password if @password_confirmation.blank?

      outcome = User.transaction do
        @user.lock!
        next USED unless @user.invited?

        @user.assign_attributes(name: @name, password: @password, password_confirmation: @password_confirmation, invited_at: nil)
        next :invalid unless @user.save

        record_event("user.invite_accepted", subject: @user, field_changes: user_field_changes(@user))
        :accepted
      end

      case outcome
      when :accepted then success(@user)
      when USED then failure(@user, [ USED ])
      else failure(@user)
      end
    end

    private

    # `has_secure_password` ignores an empty password on an existing row, so
    # a blank one would otherwise "succeed" with the random password left in
    # place and the invite cleared: a person locked out of their own account.
    def blank_password
      @user.errors.add(:password, :blank)
      failure(@user)
    end

    # As `Users::Save`: a typed password needs a typed confirmation, which
    # `has_secure_password` compares only when it is given.
    def unconfirmed_password
      @user.assign_attributes(password: @password)
      @user.validate
      @user.errors.add(:password_confirmation, :blank)
      failure(@user)
    end
  end
end
