module SignIn
  # The counters that close sign-in after repeated failures, in two buckets,
  # and say when the bot check is due. The caller asks `reserve` BEFORE it
  # checks a password, checks the password only when the reservation is
  # `ok?`, and tells `record_success` when it was right. A wrong one is not
  # told: the reservation was its count.
  #
  # WHY BEFORE. A count made after the check would let attempts that run at
  # once all pass an open bucket and all check a password before the first
  # failure closed it, so the guesses per lock would be bounded by how many
  # run at once, not by the back-off. Counted first, with one atomic
  # `increment` per bucket, parallel attempts get no more guesses per lock
  # than serial ones (`SignIn.store` names the one moment Solid Cache can
  # lose a count).
  #
  # THE ACCOUNT BUCKET counts the attempts for one identifier (the caller's
  # normalised email), whether or not an account has it, so a closed bucket
  # says nothing about who exists. The first ACCOUNT_FREE_FAILURES - 1 go
  # on freely. From the fifth on, an attempt goes on only if it is the one
  # that writes the lock its count earns (`lock_seconds`: 1 minute, doubling
  # to the 1 hour cap); the lock is written with `unless_exist`, so of two
  # that race for one lock exactly one wins, a standing lock is never
  # overwritten by a shorter one, and the loser is refused as locked. The
  # lock is written as the attempt goes on and stands if its password
  # fails; a success takes it back. A run is forgotten ACCOUNT_RUN after its
  # first attempt (without an end, one mistyped password a month would lock
  # a person on the fifth).
  #
  # A REFUSED ATTEMPT NEVER COUNTS. One refused by a standing lock is
  # refused on a read, before any increment, so a bot trying through the
  # lock does not lengthen it: once it ends, the right password signs the
  # person in and their next mistake counts from one. (A bot that tries
  # once at each lock's end can hold the account bucket closed; the known
  # device, below, is what keeps the person in.) The read
  # before the increment is safe because a lock only ever moves the answer
  # toward refusal: a lock written just after the read is met by the
  # attempt's own `unless_exist` write, which it then loses. An attempt
  # refused after its increment (it lost the race for the lock, or the
  # other bucket refused it) takes its count back with a `decrement`.
  #
  # A KNOWN DEVICE COUNTS APART. An attempt from a browser that signed in to
  # this account before (the caller hands its device id as `device:`, from a
  # cookie a bot never holds: OWASP's "device cookie") is counted in a
  # bucket of that account and that device, with the account bucket's
  # figures, and is neither counted in nor refused by the account's own
  # bucket. So a bot that closes an account at every lock's end, which the
  # account bucket alone cannot stop (one attempt an hour, from anywhere),
  # does not keep the person out of their own browser; and a device bucket
  # that closes closes that device alone. The wide bucket and the bot check
  # apply to a known device as to anyone. `clear` (a new password set by
  # anyone who proved the account) opens the account's bucket and every
  # device's at once.
  #
  # THE WIDE BUCKET counts every attempt from one address (`VisitorAddress`,
  # an IPv6 one by its /64), whatever accounts it tried: WIDE_LIMIT go on in
  # an hour from the first, and the address is then closed until that hour
  # ends. A success takes back only its own count, never the others', or
  # one account a bot holds would reopen it. It is asked first.
  #
  # THE BOT CHECK is due once the address or the account has BOT_CHECK_AFTER
  # attempts that went on, in a BOT_CHECK_WINDOW from the first, counted
  # apart from the buckets because the window is another. A success takes
  # its own back.
  #
  # THE STORE HOLDS NEITHER THE EMAIL NOR THE IP: every key is the scope, the
  # counter's name and an HMAC-SHA256 under KEY_PURPOSE, of the identifier or
  # of the normalised address. `scope` is in every key, so a members'
  # sign-in counts apart from CS Studio's.
  #
  # A window is the expiry a count's first `increment` sets, which a later
  # one keeps. An account's lock holds `[until, level]` (the epoch second it
  # ends at and its back-off level) and expires then. Integer seconds
  # throughout: a Trip's `seconds` is what is left, rounded down, or the new
  # lock's length. A nil count or a failed write (Solid Cache's failsafe) is
  # an open bucket.
  #
  # Each bucket decided is one `auth.throttle` span, `auth.tripped` when it
  # refused the attempt or the attempt closed it.
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
    # How long an account's generation is kept (`clear`). Its loss only ever
    # opens device buckets, never closes one; it outlives a device cookie's
    # 90 days so a reset is not undone by it within a cookie's life.
    GENERATION_KEPT = 1.year
    KEY_PURPOSE = "content_spiel sign-in throttle".freeze

    # A closed bucket: `:account` or `:device` with its back-off level
    # (count - 5), or `:address_wide` with none, and the seconds it stays
    # closed.
    Trip = Data.define(:bucket, :level, :seconds)

    # `refused_by`: the closed bucket that refuses the attempt, which then
    # checks no password, or nil. `closes`: the buckets the attempt closed
    # by going on, the account's then the address's; they stand when its
    # password fails (the caller audits them and mails the account's), and
    # a success takes the account's back.
    Reservation = Data.define(:refused_by, :closes) do
      def ok? = refused_by.nil?
    end

    # How long the count-th attempt of a run closes the account, or nil
    # while it is free. The shift's exponent is bounded so that a run of any
    # length stays a small number before the cap.
    def self.lock_seconds(count)
      return nil if count < ACCOUNT_FREE_FAILURES

      exponent = [ count - ACCOUNT_FREE_FAILURES, 32 ].min
      [ BACKOFF_FIRST.to_i << exponent, BACKOFF_CAP.to_i ].min
    end

    attr_reader :scope, :store

    def initialize(scope: "studio", store: SignIn.store)
      @scope = scope
      @store = store
    end

    # `device`: the id of a browser that signed in to this account before,
    # or nil.
    def reserve(identifier:, address:, device: nil)
      account = identifier_digest(identifier)
      address = address_digest(address)

      wide_refusal, wide_closes = reserve_wide(address)
      return Reservation.new(refused_by: wide_refusal, closes: []) if wide_refusal

      account_refusal, account_closes = device ? reserve_run(:device, device_digest(identifier, device)) : reserve_run(:account, account)
      if account_refusal
        take_back(key(:wide, address), WIDE_WINDOW)
        return Reservation.new(refused_by: account_refusal, closes: [])
      end

      store.increment(key(:bot_address, address), 1, expires_in: BOT_CHECK_WINDOW)
      store.increment(key(:bot_account, account), 1, expires_in: BOT_CHECK_WINDOW)
      Reservation.new(refused_by: nil, closes: [ account_closes, wide_closes ].compact)
    end

    # The attempt's password was right: the bucket it was counted in
    # forgets its run and its lock (the account's with its bot-check count,
    # or for a known device the device's alone: the account's run may be a
    # bot's, which a success on the person's own browser must not hand five
    # fresh guesses), and the address's counts take back this attempt's own.
    def record_success(identifier:, address:, device: nil)
      if device
        digest = device_digest(identifier, device)
        store.delete_multi([ key(:device, digest), key(:device_lock, digest) ])
      else
        clear(identifier: identifier)
      end
      address = address_digest(address)
      take_back(key(:wide, address), WIDE_WINDOW)
      take_back(key(:bot_address, address), BOT_CHECK_WINDOW)
      nil
    end

    # The account's run, its lock and its bot-check count are forgotten,
    # and every known device's run and lock with them: its password was set
    # by someone who proved the account (a reset's token, the current
    # password, a manager, the console), so sign-in opens for every
    # browser. A device's keys cannot be listed, so they are not deleted:
    # each names the account's generation, which this replaces, and a
    # device's next attempt reads a bucket nobody has counted in.
    def clear(identifier:)
      account = identifier_digest(identifier)
      store.delete_multi([ key(:account, account), key(:account_lock, account), key(:bot_account, account) ])
      store.write(key(:generation, account), SecureRandom.hex(8), expires_in: GENERATION_KEPT)
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
      # [refusal, closes]: one of them a Trip, or neither.
      #
      # The window's end is written by the attempt that opened it, since an
      # increment cannot say when its key expires. Were that mark lost, a
      # closed address answers the whole window as what is left.
      def reserve_wide(address)
        decide("address_wide") do
          count_key = key(:wide, address)
          next [ wide_trip(address), nil ] if store.read(count_key).to_i >= WIDE_LIMIT

          count = store.increment(count_key, 1, expires_in: WIDE_WINDOW)
          store.write(key(:wide_ends, address), now + WIDE_WINDOW.to_i, expires_in: WIDE_WINDOW) if count == 1
          if count.nil? || count < WIDE_LIMIT
            [ nil, nil ]
          elsif count == WIDE_LIMIT
            [ nil, wide_trip(address) ]
          else
            take_back(count_key, WIDE_WINDOW)
            [ wide_trip(address), nil ]
          end
        end
      end

      # The account's run, or a known device's (`bucket` :account or
      # :device), under `digest`.
      def reserve_run(bucket, digest)
        decide(bucket.to_s) do
          count_key = key(bucket, digest)
          lock_key = key(:"#{bucket}_lock", digest)
          standing = run_lock(bucket, lock_key)
          next [ standing, nil ] if standing

          count = store.increment(count_key, 1, expires_in: ACCOUNT_RUN)
          next [ nil, nil ] if count.nil? || count < ACCOUNT_FREE_FAILURES

          seconds = self.class.lock_seconds(count)
          level = count - ACCOUNT_FREE_FAILURES
          next [ nil, Trip.new(bucket: bucket, level: level, seconds: seconds) ] if store.write(lock_key, [ now + seconds, level ], unless_exist: true, expires_in: seconds)

          # Lost: another attempt's lock stands, and refuses this one. With
          # none to be read the write failed (Solid Cache's failsafe answers
          # false), and the bucket is open.
          standing = run_lock(bucket, lock_key)
          take_back(count_key, ACCOUNT_RUN) if standing
          [ standing, nil ]
        end
      end

      # The standing lock as a Trip, or nil.
      def run_lock(bucket, lock_key)
        ends, level = store.read(lock_key)
        left = seconds_until(ends)
        Trip.new(bucket: bucket, level: level, seconds: left) if left
      end

      def wide_trip(address)
        Trip.new(bucket: :address_wide, level: nil, seconds: seconds_until(store.read(key(:wide_ends, address))) || WIDE_WINDOW.to_i)
      end

      # Takes one count back, only while its window stands: a decrement of a
      # key that expired meanwhile would open the next window at -1.
      def take_back(count_key, window)
        store.decrement(count_key, 1, expires_in: window) if store.exist?(count_key)
      end

      # The block's [refusal, closes], inside one `auth.throttle` span that
      # says which bucket was decided and how.
      def decide(bucket)
        Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => bucket }) do |span|
          refusal, closes = yield
          trip = refusal || closes
          attributes = { "auth.tripped" => !trip.nil? }
          attributes["auth.backoff_level"] = trip.level if trip&.level
          Telemetry.record(span, attributes)
          [ refusal, closes ]
        end
      end

      def seconds_until(epoch)
        left = epoch.to_i - now
        left if epoch && left.positive?
      end

      def now = Time.current.to_i

      def key(counter, digest) = "sign_in:#{scope}:#{counter}:#{digest}"

      def address_digest(address) = VisitorAddress.key(address, purpose: KEY_PURPOSE)

      # An email as written, never cut as an address would be.
      def identifier_digest(identifier) = VisitorAddress.digest(identifier, purpose: KEY_PURPOSE)

      # One account on one device, in the account's current generation
      # (`clear`): one more read, on a known device's attempts only.
      def device_digest(identifier, device)
        account = identifier_digest(identifier)
        VisitorAddress.digest("#{account}:#{store.read(key(:generation, account))}:#{device}", purpose: KEY_PURPOSE)
      end
  end
end
