module SignIn
  # One sign-in with an email address and a password, decided: the bot
  # check when it is due, the throttle's reservation, the password, in that
  # order, answered as a `SignIn::Outcome`. It knows no session, cookie,
  # route or mail: the caller signs the account in, audits, mails and
  # answers.
  #
  # THE ORDER, and why each step stands where it does:
  #
  # 1. The bot check, when the site has one (`SignIn::BotCheck.current`)
  #    and the address or the email is due (`Throttle#bot_check_due?`). A
  #    missing or junk token is `:bot_check_required`, a token Cloudflare
  #    refuses `:bot_check_failed`. It comes before the reservation, so an
  #    attempt the check refuses counts nothing and checks no password: a
  #    bot without a token costs the account nothing and learns nothing.
  #    Cloudflare unreachable (`:unavailable`) goes on as if it passed.
  # 2. The reservation (`Throttle#reserve`), which counts the attempt in the
  #    account's bucket (or, from a browser that signed in to it before,
  #    `device`, that device's) and the address's BEFORE the password is
  #    checked, so attempts at once get no more guesses per lock than
  #    attempts one after another. A closed bucket is `:locked`, with no password checked.
  # 3. The password, through `accounts.authenticate_by`, which hashes the
  #    password whether or not the address has an account (`User.new(password:)`
  #    for an unknown one), so a refusal takes the same work either way.
  # 4. A right password gives the attempt's counts back
  #    (`Throttle#record_success`) and is `:ok`; a wrong one is `:refused`
  #    with the buckets its reservation closed, and is counted no further:
  #    the reservation was its count. A right password for an account that
  #    holds a second factor (`User#second_factor?`) is
  #    `:second_factor_required` (`Throttle#await_second_proof`): the
  #    address's counts are given back, and so is a lock its own
  #    reservation wrote, but the account's (or the device's) count stands
  #    until the second proof (`SignIn::Proof`) succeeds, so the password
  #    alone never clears a run nor signs anyone in.
  #
  # The email and the password reach `authenticate_by` as Strings, a list or
  # a hash as "", so a junk parameter is refused as any wrong address is and
  # counts in the bucket of "". So is an email Postgres would refuse to
  # compare (a NUL byte, or bytes that are no UTF-8): it is made "" before
  # the reservation (`#email`), so it is counted as an ordinary refusal and
  # never reaches a query, nor the caller's audit metadata, as an error
  # after its count. The account bucket's identifier is the email
  # as `accounts` normalises it, so " Ann@Example.ORG " and "ann@example.org"
  # are one bucket, and a long address counts whole.
  #
  # One `auth.sign_in` span holds the attempt: `auth.outcome` at the end,
  # `auth.bot_check.required` when the site has a check, and
  # `auth.account_exists` once a password was checked (`authenticate_by`
  # checks none for an empty one), and `auth.second_factor.required` when
  # a right password still owes a second proof. `auth.account_exists` is
  # asked with one more query on a refusal, for a known and an unknown
  # address alike, and never reaches the answer.
  class PasswordAttempt
    attr_reader :address

    # `device`: the `KnownDevice` the browser carries, or nil.
    def initialize(email:, password:, address:, hostname:, bot_check_token:, device: nil, accounts: User, throttle: SignIn::Throttle.new, bot_check: SignIn::BotCheck.current)
      @email = email
      @device = device
      @password = password
      @address = address
      @hostname = hostname
      @bot_check_token = bot_check_token
      @accounts = accounts
      @throttle = throttle
      @bot_check = bot_check
    end

    # The email as it is looked up: the String typed, or "" for anything
    # else (no String, a NUL byte, bytes that are no UTF-8). The caller keeps
    # this one, never the raw parameter.
    def email
      @email_text ||= @email.is_a?(String) && @email.valid_encoding? && !@email.include?("\0") ? @email : ""
    end

    # The account bucket's key: the email as the accounts store it.
    def identifier
      @identifier ||= @accounts.normalize_value_for(:email_address, email)
    end

    def call
      Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password" }) do |span|
        decide(span).tap { |outcome| Telemetry.record(span, "auth.outcome" => outcome.status.to_s) }
      end
    end

    private

    def decide(span)
      if @bot_check
        due = @throttle.bot_check_due?(address: address, identifier: identifier)
        Telemetry.record(span, "auth.bot_check.required" => due)
        if due
          return outcome(:bot_check_required, bot_check_due: true) unless BotCheck.usable_token?(@bot_check_token)
          return outcome(:bot_check_failed, bot_check_due: true) if @bot_check.verify(@bot_check_token, address: address, hostname: @hostname) == :failed
        end
      end

      reservation = @throttle.reserve(identifier: identifier, address: address, device: known_device_id)
      return outcome(:locked, trips: [ reservation.refused_by ]) unless reservation.ok?

      password = @password.is_a?(String) ? @password : ""
      account = @accounts.authenticate_by(email_address: email, password: password)
      Telemetry.record(span, "auth.account_exists" => account.present? || @accounts.exists?(email_address: email)) unless password.empty?
      return outcome(:refused, trips: reservation.closes) unless account

      if account.second_factor?
        @throttle.await_second_proof(reservation, identifier: identifier, address: address, device: known_device_id)
        Telemetry.record(span, "auth.second_factor.required" => true)
        return outcome(:second_factor_required, account: account)
      end

      @throttle.record_success(identifier: identifier, address: address, device: known_device_id)
      outcome(:ok, account: account)
    end

    # The device's id when it has signed in to this account before.
    def known_device_id
      @device.id if @device&.knows?(identifier)
    end

    def outcome(status, account: nil, trips: [], bot_check_due: bot_check_due?)
      Outcome.new(status: status, account: account, trips: trips, bot_check_due: bot_check_due)
    end

    def bot_check_due?
      !@bot_check.nil? && @throttle.bot_check_due?(address: address, identifier: identifier)
    end
  end
end
