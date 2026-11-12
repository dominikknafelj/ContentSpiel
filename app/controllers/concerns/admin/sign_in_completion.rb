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

    private

    # `method` is how the person proved it (`Session::METHODS`);
    # `session.created` names it unless it is the password.
    def complete_sign_in(user, method:)
      session.delete(:sign_in_bot_check)
      start_new_session_for(user, method: method)
      remember_device(User.normalize_value_for(:email_address, user.email_address))
      Current.actor = user
      Audit.record("session.created", subject: user, metadata: method == "password" ? {} : { "method" => method })
      nil
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
