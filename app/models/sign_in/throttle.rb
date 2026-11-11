module SignIn
  # The counters that close sign-in after repeated failures, in two buckets,
  # and say when the bot check is due. The caller asks `closed` before it
  # checks a password, and tells `record_failure` or `record_success` after.
  #
  # THE ACCOUNT BUCKET counts the failures for one identifier (the caller's
  # normalised email), whether or not an account has it, so a closed bucket
  # says nothing about who exists. The first ACCOUNT_FREE_FAILURES - 1 cost
  # nothing; from the fifth on, each failure closes the bucket for
  # `lock_seconds(failures)`: 1 minute, doubling to the 1 hour cap. A run is
  # forgotten ACCOUNT_RUN after its first failure (without an end, one
  # mistyped password a month would lock a person on the fifth), and a
  # success forgets it at once.
  #
  # An attempt while a bucket is closed checks no password and counts
  # nothing: `closed` only reads. Counting such attempts would let a bot keep
  # the person out for good; this way, once the lock ends, the right password
  # signs them in and their next mistake counts from one.
  #
  # THE WIDE BUCKET counts every failure from one address (`VisitorAddress`,
  # an IPv6 one by its /64), whatever accounts it tried: the fiftieth in an
  # hour from the first closes the address until that hour ends. A success
  # does not clear it, or one account a bot holds would reopen it. `closed`
  # asks it first.
  #
  # THE BOT CHECK is due once the address or the account has BOT_CHECK_AFTER
  # failures in a BOT_CHECK_WINDOW from the first, counted apart from the
  # buckets' own counts because the window is another.
  #
  # THE STORE HOLDS NEITHER THE EMAIL NOR THE IP: every key is the scope, the
  # counter's name and an HMAC-SHA256 under KEY_PURPOSE, of the identifier or
  # of the normalised address. `scope` is in every key, so a members'
  # sign-in counts apart from CS Studio's.
  #
  # A window is the expiry a count's first `increment` sets, which a later
  # one keeps (`SignIn.store`). A lock is a key holding the epoch second it
  # ends at, expiring then. Integer seconds throughout: a Trip's `seconds`
  # is what is left, rounded down, or the new lock's length.
  #
  # Each bucket decided is one `auth.throttle` span: `closed` makes one per
  # bucket asked, `record_failure` one per bucket the failure closed.
  class Throttle
    ACCOUNT_FREE_FAILURES = 5
    BACKOFF_FIRST = 1.minute
    BACKOFF_CAP = 1.hour
    ACCOUNT_RUN = 24.hours
    WIDE_LIMIT = 50
    WIDE_WINDOW = 1.hour
    BOT_CHECK_AFTER = 3
    BOT_CHECK_WINDOW = 15.minutes
    NOTICE_EVERY = 1.hour
    KEY_PURPOSE = "content_spiel sign-in throttle".freeze

    # A closed bucket: `:account` with its back-off level (failures - 5), or
    # `:address_wide` with none, and the seconds it stays closed.
    Trip = Data.define(:bucket, :level, :seconds)

    # How long the failure-th failure of a run closes the account, or nil
    # while it is free. The shift's exponent is bounded so that a run of any
    # length stays a small number before the cap.
    def self.lock_seconds(failures)
      return nil if failures < ACCOUNT_FREE_FAILURES

      exponent = [ failures - ACCOUNT_FREE_FAILURES, 32 ].min
      [ BACKOFF_FIRST.to_i << exponent, BACKOFF_CAP.to_i ].min
    end

    attr_reader :scope, :store

    def initialize(scope: "studio", store: SignIn.store)
      @scope = scope
      @store = store
    end

    def closed(identifier:, address:)
      wide_closed(address_digest(address)) || account_closed(identifier_digest(identifier))
    end

    # Counts one checked password that failed, and answers the bucket it
    # closed. Were both to close on one failure, the wide one is answered,
    # as `closed` would answer it next; the account's lock is written all
    # the same.
    def record_failure(identifier:, address:)
      account = identifier_digest(identifier)
      address = address_digest(address)
      store.increment(key(:bot_address, address), 1, expires_in: BOT_CHECK_WINDOW)
      store.increment(key(:bot_account, account), 1, expires_in: BOT_CHECK_WINDOW)

      account_trip = count_account(account)
      count_wide(address) || account_trip
    end

    def record_success(identifier:)
      account = identifier_digest(identifier)
      store.delete_multi([ key(:account, account), key(:account_lock, account), key(:bot_account, account) ])
      nil
    end

    def bot_check_due?(address:, identifier: nil)
      return true if store.read(key(:bot_address, address_digest(address))).to_i >= BOT_CHECK_AFTER

      !identifier.nil? && store.read(key(:bot_account, identifier_digest(identifier))).to_i >= BOT_CHECK_AFTER
    end

    # True once an hour per account, and writes the hour's mark: the caller
    # mails when it is true, so a doubling lock mails at most once an hour.
    def notice_due?(identifier:)
      store.write(key(:notice, identifier_digest(identifier)), true, unless_exist: true, expires_in: NOTICE_EVERY) ? true : false
    end

    private
      def wide_closed(address)
        decide("address_wide") do
          left = seconds_until(store.read(key(:wide_ends, address)))
          Trip.new(bucket: :address_wide, level: nil, seconds: left) if left && store.read(key(:wide, address)).to_i >= WIDE_LIMIT
        end
      end

      # The level is nil when the run's count was forgotten while its last
      # lock still stands (a lock of the run's last hour outlives the run).
      def account_closed(account)
        decide("account") do
          left = seconds_until(store.read(key(:account_lock, account)))
          Trip.new(bucket: :account, level: level(store.read(key(:account, account))), seconds: left) if left
        end
      end

      def count_account(account)
        failures = store.increment(key(:account, account), 1, expires_in: ACCOUNT_RUN)
        seconds = self.class.lock_seconds(failures)
        return unless seconds

        store.write(key(:account_lock, account), now + seconds, expires_in: seconds)
        decide("account") { Trip.new(bucket: :account, level: level(failures), seconds: seconds) }
      end

      # The window's end is written by the failure that opened it, since an
      # increment cannot say when its key expires. Were that mark evicted,
      # the bucket stays open: an eviction may open a bucket early and never
      # closes one.
      def count_wide(address)
        failures = store.increment(key(:wide, address), 1, expires_in: WIDE_WINDOW)
        store.write(key(:wide_ends, address), now + WIDE_WINDOW.to_i, expires_in: WIDE_WINDOW) if failures == 1
        return unless failures == WIDE_LIMIT

        left = seconds_until(store.read(key(:wide_ends, address)))
        decide("address_wide") { Trip.new(bucket: :address_wide, level: nil, seconds: left) } if left
      end

      # The block's Trip or nil, inside one `auth.throttle` span that says
      # which bucket was decided and how.
      def decide(bucket)
        Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => bucket }) do |span|
          trip = yield
          attributes = { "auth.tripped" => !trip.nil? }
          attributes["auth.backoff_level"] = trip.level if trip&.level
          Telemetry.record(span, attributes)
          trip
        end
      end

      def level(failures) = failures && failures - ACCOUNT_FREE_FAILURES

      def seconds_until(epoch)
        left = epoch.to_i - now
        left if epoch && left.positive?
      end

      def now = Time.current.to_i

      def key(counter, digest) = "sign_in:#{scope}:#{counter}:#{digest}"

      def address_digest(address) = VisitorAddress.key(address, purpose: KEY_PURPOSE)

      # The identifier as the store knows it, under the same purpose's secret
      # as the address (the key generator caches it).
      def identifier_digest(identifier)
        OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key(KEY_PURPOSE), identifier.to_s)
      end
  end
end
