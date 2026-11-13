module Admin
  # What every whole sign-in to CS Studio does once its person has proved
  # who they are, however they proved it: the session, the known device,
  # `session.created`, and forgetting the bot check's flag.
  #
  # THE KNOWN DEVICE (`SignIn::KnownDevice`) is written here and nowhere
  # else, so only a whole sign-in earns one: never a password step that
  # still owes its second proof, or a stolen password would earn its own
  # device bucket beside the account's lock. A bot never holds one, and it
  # is read back on every attempt, so a browser that signed in to an account
  # before is counted apart from the account's bucket a bot may hold closed.
  # Encrypted and signed (`cookies.encrypted`): a cookie that does not open,
  # or that names another account, is no known device and the attempt goes
  # the common way. HttpOnly, SameSite Lax, Secure where the site is HTTPS,
  # for DEVICE_LIFETIME from its last sign-in. It holds a random id and the
  # HMACs of the accounts, never an email.
  module SignInCompletion
    DEVICE_COOKIE = :cs_known_device
    DEVICE_LIFETIME = 90.days
    # The ways in that are the site's own, which an owner may use: proved
    # here, against what the site holds, never vouched for by a provider.
    OWN_METHODS = %w[password passkey recovery_code].freeze

    private

    # `method` is how the person proved it: one of `Session::METHODS`, or a
    # gem's method registered in `SignIn::Methods`; any other raises
    # `ArgumentError`, before anything is written. `session.created` names
    # the method unless it is the password. `provider_token` is an outside
    # provider's refresh token, kept on the session (`Session.start`) for
    # its daily re-check.
    #
    # True when the person is signed in. FALSE, with nothing written, for an
    # owner by an OUTSIDE METHOD (any but OWN_METHODS: single sign-on, or a
    # gem's): an owner keeps a way in of their own, which no outside service
    # may stand in for (`SignIn::Rules`). The caller answers a false as its
    # own refusal. This is the hook's promise to a gem's method
    # (`docs/reference/content-blocks-and-types.md`), so it is decided here
    # and not left to each caller.
    def complete_sign_in(user, method:, provider_token: nil)
      method = method.to_s
      raise ArgumentError, "#{method.inspect} is no sign-in method" unless (Session::METHODS + SignIn::Methods.names).include?(method)
      return false if user.owner? && !OWN_METHODS.include?(method)

      session.delete(:sign_in_bot_check)
      start_new_session_for(user, method: method, provider_token: provider_token)
      remember_device(User.normalize_value_for(:email_address, user.email_address))
      Current.actor = user
      Audit.record("session.created", subject: user, metadata: method == "password" ? {} : { "method" => method })
      true
    end

    def known_device = SignIn::KnownDevice.read(cookies.encrypted[DEVICE_COOKIE])

    def remember_device(identifier)
      cookies.encrypted[DEVICE_COOKIE] = {
        value: known_device.remember(identifier).to_h,
        expires: DEVICE_LIFETIME, httponly: true, same_site: :lax, secure: request.ssl?
      }
    end
  end
end
