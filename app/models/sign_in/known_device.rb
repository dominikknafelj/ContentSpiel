module SignIn
  # A browser that has signed in before: a random id of its own and the
  # accounts it signed in to, as the keys `account_key` makes (an HMAC of
  # the normalised email, never the email). The caller keeps it where only
  # that browser has it (CS Studio: an encrypted cookie, written only after
  # a right password, so a bot never holds one) and hands it to
  # `PasswordAttempt` as `device:`; an attempt for an account the device
  # knows is counted in that device's bucket (`Throttle`, "A KNOWN DEVICE").
  #
  # `from` takes whatever the caller read back and trusts nothing in it: a
  # value of another shape, an id or a key that is not hex of its length,
  # is a device that knows no account. It remembers MAX_ACCOUNTS accounts,
  # the latest first.
  class KnownDevice
    MAX_ACCOUNTS = 5
    KEY_PURPOSE = "content_spiel sign-in known device".freeze
    ID = /\A\h{32}\z/
    ACCOUNT_KEY = /\A\h{64}\z/

    attr_reader :id, :accounts

    def self.account_key(identifier) = VisitorAddress.digest(identifier, purpose: KEY_PURPOSE)

    # A device from what the caller stored (`to_h`), or a new one that
    # knows no account.
    def self.from(value)
      return new unless value.is_a?(Hash) && value["id"].is_a?(String) && value["id"].match?(ID) && value["accounts"].is_a?(Array)

      new(id: value["id"], accounts: value["accounts"].grep(String).select { |key| key.match?(ACCOUNT_KEY) }.first(MAX_ACCOUNTS))
    end

    def initialize(id: SecureRandom.hex(16), accounts: [])
      @id = id
      @accounts = accounts.freeze
    end

    def knows?(identifier) = accounts.include?(self.class.account_key(identifier))

    # The same device, knowing `identifier`'s account first.
    def remember(identifier)
      key = self.class.account_key(identifier)
      self.class.new(id: id, accounts: [ key, *(accounts - [ key ]) ].first(MAX_ACCOUNTS))
    end

    def to_h = { "id" => id, "accounts" => accounts }
  end
end
