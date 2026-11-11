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
# THE STORE is `CounterStore.current`, captured when the class is defined:
# the one every counter of the site shares, Solid Cache in production and a
# memory store of the process in tests (it says why).
module MailTestLimit
  extend ActiveSupport::Concern

  NAME = "mail_test".freeze
  LIMIT = 5
  WITHIN = 3.minutes

  def self.store = CounterStore.current

  class_methods do
    def limit_test_mails(with:, **options)
      rate_limit to: LIMIT, within: WITHIN, name: NAME, scope: NAME, store: MailTestLimit.store,
        by: -> { Current.user ? "user-#{Current.user.id}" : request.remote_ip }, with: with, **options
    end
  end
end
