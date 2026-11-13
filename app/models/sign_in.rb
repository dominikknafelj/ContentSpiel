# What any kind of sign-in calls to decide an attempt: plain objects that
# count attempts, close buckets and say when a check is due
# (`SignIn::Throttle`), and that make and check passkeys
# (`SignIn::PasskeyRegistration`, `SignIn::PasskeyCheck`, over the one
# relying party `SignIn::RelyingParty` decides: the one place the domain a
# passkey belongs to is decided), and that speak to the site's single
# sign-on provider (`SignIn::Oidc`: its discovery, keys, authorization
# request and tokens). Nothing here knows a session, a cookie, a
# route, a controller or a mail: a controller asks and answers (and keeps a
# passkey's challenge), a job mails. CS Studio's sign-in is one caller; a
# later members' sign-in is another, and counts apart under a scope of its
# own.
module SignIn
  # What a sign-in attempt can come to (`SignIn::Outcome#status`), and the
  # words its span's `auth.outcome` may carry. The last three are single
  # sign-on's alone: a callback that did not finish (`auth.sso.callback`),
  # and a session's daily re-check that the provider refused or could not
  # answer (`auth.sso.recheck`).
  OUTCOMES = %i[ok refused locked bot_check_required bot_check_failed second_factor_required unfinished revoked unavailable].freeze

  # How long a right password waits for its second proof (a passkey or a
  # recovery code) before the person starts over.
  SECOND_STEP_LIFETIME = 5.minutes

  # Where the throttle's counters live: `CounterStore.current`, Solid Cache
  # in production (every process counts in one place) and one memory store
  # of the process in tests, cleared before each.
  #
  # WHAT THE THROTTLE RELIES ON, read in solid_cache 1.0.10 and Active
  # Support's `MemoryStore`:
  #
  # - A later `increment` keeps the first write's expiry
  #   (`SolidCache::Store::Api#adjusted_entry` builds the new entry with
  #   `expires_at: entry.expires_at`; `MemoryStore#modify_value` likewise),
  #   so a window opened by a count's first `increment(key, 1, expires_in:)`
  #   ends where it began, as Rails' `rate_limit` relies on, and a key need
  #   not carry its window's start.
  # - `MemoryStore#increment` runs under the store's monitor: atomic.
  #   Solid Cache's is a transaction that reads the row `FOR UPDATE` and
  #   upserts the sum (`SolidCache::Entry.lock_and_write`), not one SQL
  #   statement that adds: atomic once the row exists, an expired row
  #   included; its `write(…, unless_exist: true)` is the same transaction
  #   around a check. A key's FIRST write locks no row, so two increments
  #   at the same instant both read nothing and both write 1, and two
  #   `unless_exist` writes both write: one attempt is not counted, or two
  #   win one lock. Each such loss is one more attempt, only at the moment
  #   a key is first written (a new email or address, an account's first
  #   lock, or an account just cleared by a success). Closing it would take
  #   a table of our own with an `INSERT … ON CONFLICT DO UPDATE SET n =
  #   n + 1`.
  # - Solid Cache's failsafe answers nil for an `increment` that met a
  #   transient database error, and may evict an entry early when the cache
  #   is full (`max_size`, `config/cache.yml`). The throttle takes a nil
  #   count as an open bucket: a cache outage opens sign-in's throttles and
  #   never answers 500 or closes one.
  def self.store = CounterStore.current
end
