# The sign-in domain: everything that signs a person in, one namespace across
# the layer folders (app/models/sign_in/, app/services/sign_in/,
# app/jobs/sign_in/), two levels deep and no deeper.
#
# The root holds the shared core:
#
# - `SignIn::Rules`: who may sign in how (a linked account never by password
#   or passkey; a non-owner never while single sign-on is required).
# - `SignIn::Methods`: the registry of ways in, filled by the gem hook.
# - `SignIn::Proof`: the second proof of the second step, and Confirm it's you.
# - `SignIn::Outcome`: what an attempt came to, one of `OUTCOMES`.
# - `SignIn::SpentChallenge`: a challenge or a state spent once.
# - `SignIn::OutsideCall`: a call to another service, timed and spanned.
#
# And six sub-namespaces:
#
# - `SignIn::Protection`: the throttle, the bot check, the known device and
#   the lockout mail's job.
# - `SignIn::Password`: the password attempt, the leaked-password check and
#   the rule the services that set a password include.
# - `SignIn::Passkeys`: the ceremonies (registration, check, credential) over
#   the one relying party (the one place a passkey's domain is decided), the
#   passkey policy, and the add, remove and rename services.
# - `SignIn::RecoveryCodes`: making a set of recovery codes.
# - `SignIn::Sessions`: ending sessions, and the hourly sweep.
# - `SignIn::Sso`: single sign-on, its protocol objects (provider,
#   authorization, callback, ID token, refresh), the services that admit, link
#   and unlink an account, and the daily re-check's job.
#
# Two kinds live here. The root, Protection, Password, the passkey ceremonies
# and Sso's protocol objects are plain objects that know no session, cookie,
# route, controller or mail: CS Studio's sign-in is one caller, and a later
# members' sign-in is another that counts apart under a scope of its own. The
# services and jobs (`SignIn::Passkeys::Add`, `Remove` and `Rename`,
# `SignIn::RecoveryCodes`, `SignIn::Sessions`, and `SignIn::Sso::Admit`,
# `Link`, `Unlink` and `RecheckJob`) act on CS Studio's `User` and `Session`. The screens that ask the domain stay CS Studio's own,
# under `Admin::`: a controller asks and answers (and keeps a passkey's
# challenge), and the domain names none of them.
#
# Two guards hold the shape: `test/lib/sign_in_namespace_shadow_test.rb` (no
# name under `SignIn` is a top-level constant's, nothing deeper than two
# levels) and `test/lib/sign_in_boundary_test.rb` (code outside reaches the
# domain only through its named entry points, and the domain names no screen).
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
