# What any kind of sign-in calls to decide an attempt: plain objects that
# count failures, close buckets and say when a check is due
# (`SignIn::Throttle`). Nothing here knows a session, a cookie, a route, a
# controller or a mail: a controller asks and answers, a job mails. CS
# Studio's sign-in is one caller; a later members' sign-in is another, and
# counts apart under a scope of its own.
module SignIn
  # Where the throttle's counters live: `Rails.cache`, unless that is an
  # `ActiveSupport::Cache::NullStore` (the test environment's), whose every
  # write is a no-op and whose throttle could never trip; there it is one
  # `MemoryStore` of the process, which `test/test_helper.rb` clears before
  # every test. The rule `MailTestLimit.store` and `Forms::SendLimit.store`
  # follow.
  #
  # In production `Rails.cache` is Solid Cache, a table of the database, so
  # every process and every container of the site counts in one place. Its
  # `increment` keeps the first write's expiry (`SolidCache::Store::Api#
  # adjusted_entry` builds the new entry with `expires_at: entry.expires_at`;
  # `MemoryStore#modify_value` does the same), so a window opened by a
  # count's first `increment(key, 1, expires_in:)` ends where it began, as
  # Rails' `rate_limit` relies on, and a key need not carry its window's
  # start. A Solid Cache entry may be evicted early when the cache is full
  # (its `max_size`, `config/cache.yml`): a count then starts again, which
  # can open a bucket early and never closes one.
  def self.store
    @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end
end
