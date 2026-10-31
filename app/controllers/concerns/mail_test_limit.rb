# The one limit on test mails (spec, "Rate limits": 5 per person per 3
# minutes; plan Ruling P2): Settings → Mail's "Send test mail"
# (`Admin::SettingsController#send_test_mail`) and the setup wizard's mail
# step share it, because the figure is per PERSON, not per screen.
#
#   include MailTestLimit
#   limit_test_mails only: :send_test_mail, with: -> { ... answer ... }
#
# ONE BUCKET. Rails' `rate_limit` counts under
# `rate-limit:<scope>:<name>:<by>`, and `scope` defaults to the controller's
# path, so two controllers that only shared a `name:` would count apart.
# Both are given here, the same for every includer, and `by` is the signed-in
# person (a test mail is sent to them; nobody signed in has no test mail to
# send, and counts by address).
#
# THE STORE is captured when the class is defined. It is `Rails.cache` (Solid
# Cache in production, shared by every process), unless that is a
# `NullStore` (the test environment's), whose every write is a no-op: a limit
# that can never trip is no limit, so there it is one memory store for the
# process (`store`, which a test clears).
module MailTestLimit
  extend ActiveSupport::Concern

  NAME = "mail_test".freeze
  LIMIT = 5
  WITHIN = 3.minutes

  def self.store
    @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end

  class_methods do
    def limit_test_mails(with:, **options)
      rate_limit to: LIMIT, within: WITHIN, name: NAME, scope: NAME, store: MailTestLimit.store,
        by: -> { Current.user ? "user-#{Current.user.id}" : request.remote_ip }, with: with, **options
    end
  end
end
