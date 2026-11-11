# The one store the site's counters keep their counts in: Rails' `rate_limit`
# for test mails (`MailTestLimit`) and a visitor's form sends
# (`Forms::SendLimit`), and sign-in's throttle (`SignIn.store`).
#
# It is `Rails.cache`, unless that is an `ActiveSupport::Cache::NullStore`
# (the test environment's), whose every write is a no-op and whose limits
# could never trip: there it is one `MemoryStore` of the process, which
# `test/test_helper.rb` clears before every test. Memoised, so a counter
# reads what it wrote; captured at its first call, so a test that swaps
# `Rails.cache` later does not move the counters.
#
# In production `Rails.cache` is Solid Cache, a table of the database, so
# every process and every container of the site counts in one place.
module CounterStore
  def self.current
    @current ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end
end
