require "test_helper"

# The digest: which alerts are mailed, to whom, how often, that nothing is
# marked while no mail can go or by a send that failed, and the retries
# after a failed send.
class Alerts::MailingTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  include LogCapture

  SITE = "https://docs.example.org".freeze
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  setup do
    Alerts::Alert.delete_all
    travel_to NOW
    ActionMailer::Base.deliveries.clear
    @owners = [ users(:one), users(:reader).tap { it.update_columns(owner: true) } ]
  end

  def make(seen: NOW - 1.minute, mailed: nil, kind: "error")
    Alerts::Alert.create!(kind: kind, fingerprint: SecureRandom.hex(8), details: { "error_class" => "RuntimeError", "place" => nil },
                          first_seen_at: seen, last_seen_at: seen, mailed_at: mailed)
  end

  # The waits between attempts are recorded, never slept.
  def deliver(now: Time.current)
    @waits = []
    Alerts::Mailing.new(now: now, wait: ->(seconds) { @waits << seconds }).deliver
  end

  # The digest's sends raise `errors` in turn, each marked a delivery's error
  # as `SmtpDelivery` marks one, then go through as they would.
  def failing_sends(*errors)
    original = Alerts::DigestMailer.method(:digest)
    tries = 0
    failing = Struct.new(:error) { def deliver_now = raise(error) }
    build = lambda do |*args|
      tries += 1
      error = errors.shift
      error ? failing.new(MailFailure.mark(error, :mail)) : original.call(*args)
    end
    with_singleton_override(Alerts::DigestMailer, :digest, build) { yield -> { tries } }
  end

  def sent_to = ActionMailer::Base.deliveries.flat_map(&:to)

  # The mail settings point at a port on this machine nobody listens on: a
  # send is refused at once, a failure of the delivery.
  def refused = { mail_server: SmtpStub::HOST, mail_port: SmtpStub.closed_port }

  def tried_at(alert) = alert.reload.digest_failed_at

  test "two due alerts and two owners: one mail each, and both alerts are marked mailed now" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        older = make(seen: NOW - 5.minutes)
        newer = make(seen: NOW - 1.minute)
        ids = [ newer.id, older.id ]

        assert_emails(2) { assert_equal 2, deliver }
        assert_equal @owners.map(&:email_address).sort, sent_to.sort
        assert_equal [ NOW ], [ older, newer ].map { it.reload.mailed_at }.uniq
      end
    end
  end

  test "a second digest waits ten minutes after the last" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        make
        assert_equal 2, deliver

        travel 9.minutes
        make
        assert_no_emails { assert_equal 0, deliver }

        travel 1.minute
        assert_emails(2) { assert_equal 2, deliver }
      end
    end
  end

  test "an alert seen again is mailed again an hour after its mail, not before" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        alert = make(seen: NOW - 70.minutes, mailed: NOW - 59.minutes)
        alert.update_columns(last_seen_at: NOW - 1.minute)
        assert_no_emails { assert_equal 0, deliver }

        travel 2.minutes
        assert_emails(2) { assert_equal 2, deliver }
        assert_equal Time.current, alert.reload.mailed_at
      end
    end
  end

  test "an alert mailed and not seen since is not mailed again" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        make(seen: NOW - 3.hours, mailed: NOW - 2.hours)
        assert_no_emails { assert_equal 0, deliver }
      end
    end
  end

  test "with mail not ready nothing is queued or marked, and one line naming nobody is logged once an hour" do
    with_mail_state(:not_set_up) do
      with_site_address(SITE) do
        alert = make
        log = capture_log do
          assert_no_emails { assert_equal 0, deliver }
          travel 30.minutes
          assert_no_emails { assert_equal 0, deliver }
        end

        assert_nil alert.reload.mailed_at
        assert_equal [ Alerts::Mailing::NOT_READY ], log.lines.map(&:strip).grep(/ContentSpiel/)
        @owners.each { assert_not_includes log, it.email_address }

        travel 31.minutes
        assert_equal [ Alerts::Mailing::NOT_READY ], capture_log { deliver }.lines.map(&:strip).grep(/ContentSpiel/)
      end
    end
  end

  test "with no address to link to nothing is queued or marked" do
    with_mail_state(:working) do
      with_site_address(nil) do
        alert = make
        log = capture_log do
          assert_no_emails { assert_equal 0, deliver }
        end

        assert_nil alert.reload.mailed_at
        assert_equal [ Alerts::Mailing::NO_ADDRESS ], log.lines.map(&:strip).grep(/ContentSpiel/)
      end
    end
  end

  test "blocked_by: nothing while mail works and an address is known, else why, any mail state but working first" do
    with_mail_state(:working) do
      with_site_address(SITE) { assert_nil Alerts::Mailing.blocked_by }
      with_site_address(nil) { assert_equal :no_address, Alerts::Mailing.blocked_by }
    end
    { not_set_up: :mail_not_set_up, untested: :mail_untested, failed: :mail_failed }.each do |state, reason|
      with_mail_state(state) do
        with_site_address(SITE) { assert_equal reason, Alerts::Mailing.blocked_by, state }
        with_site_address(nil) { assert_equal reason, Alerts::Mailing.blocked_by, "#{state} wins over the missing address" }
      end
    end
  end

  test "a failed send marks nothing, records the try, and the next waits ten minutes, then thirty, then an hour, never longer" do
    with_site_address(SITE) do
      with_mail_state(:failed, **refused) do
        alert = make
        log = capture_log { assert_no_emails { assert_equal 0, deliver } }

        assert_nil alert.reload.mailed_at, "a send that failed marks nothing"
        assert_equal [ 1, NOW ], [ alert.digest_failures, alert.digest_failed_at ]
        assert_equal NOW, SiteSetting.instance.reload.mail_failed_at, "the failure is the site's mail state, as any mail's"
        ours = log.lines.map(&:strip).grep(/ContentSpiel/)
        assert_equal [ format(Alerts::Mailing::RETRYING, 10) ], ours, "one line of its own, naming nobody"

        [ [ 10, 2 ], [ 30, 3 ], [ 60, 4 ], [ 60, 5 ] ].each do |minutes, failures|
          travel (minutes - 1).minutes
          last = tried_at(alert)
          capture_log { assert_equal 0, deliver }
          assert_equal last, tried_at(alert), "no try #{minutes - 1} minutes after a failure, with #{failures - 1} failed"

          travel 1.minute
          capture_log { assert_equal 0, deliver }
          assert_equal [ failures, Time.current ], [ alert.reload.digest_failures, alert.digest_failed_at ],
            "tried again #{minutes} minutes after the failure"
          assert_nil alert.mailed_at
        end
      end
    end
  end

  test "a connection failure is tried again: once refused, then sent, records no failure" do
    with_site_address(SITE) do
      with_mail_state(:working) do
        alert = make
        failing_sends(Errno::ECONNREFUSED.new) do |tries|
          assert_emails(2) { assert_equal 2, deliver }
          assert_equal 3, tries.call, "the first owner's send twice, the second's once"
        end
        assert_equal [ Alerts::Mailing::ATTEMPT_WAITS.first ], @waits
        assert_equal [ NOW, 0 ], [ alert.reload.mailed_at, alert.digest_failures ]
        assert_nil SiteSetting.instance.reload.mail_failed_at
        assert_equal :working, MailSettings.current.state
      end
    end
  end

  test "a connection failure on every attempt is recorded once, after the last, and starts the backoff" do
    with_site_address(SITE) do
      with_mail_state(:working) do
        alert = make
        recorded = 0
        record = MailSettings.method(:record_failure!)
        with_singleton_override(MailSettings, :record_failure!, ->(**args) { recorded += 1; record.call(**args) }) do
          failing_sends(*Array.new(Alerts::Mailing::ATTEMPTS * 2) { Net::OpenTimeout.new }) do |tries|
            capture_log { assert_no_emails { assert_equal 0, deliver } }
            assert_equal MailDeliveryJob::ATTEMPTS, tries.call, "as many attempts as a queued mail's; the other owner is not tried on a server that does not answer"
          end
        end
        assert_equal Alerts::Mailing::ATTEMPT_WAITS, @waits
        assert_equal 1, recorded
        assert_equal :failed, MailSettings.current.state
        assert_equal [ nil, 1, NOW ], [ alert.reload.mailed_at, alert.digest_failures, alert.digest_failed_at ]
      end
    end
  end

  test "a refused login is recorded at once and not tried again" do
    with_site_address(SITE) do
      with_mail_state(:working) do
        alert = make
        failing_sends(*Array.new(4) { Net::SMTPAuthenticationError.new("535 5.7.8 Authentication failed") }) do |tries|
          capture_log { assert_equal 0, deliver }
          assert_equal 2, tries.call, "one attempt for each owner"
        end
        assert_empty @waits
        assert_equal :failed, MailSettings.current.state
        assert_equal [ nil, 1 ], [ alert.reload.mailed_at, alert.digest_failures ]
      end
    end
  end

  test "a success after failed sends marks the alerts mailed, makes mail working and starts the backoff again" do
    with_site_address(SITE) do
      with_mail_state(:failed) do
        alert = make
        alert.update_columns(digest_failures: 3, digest_failed_at: NOW - 30.minutes)
        assert_no_emails { assert_equal 0, deliver }

        travel 30.minutes
        assert_emails(2) { assert_equal 2, deliver }
        assert_equal [ Time.current, 0, nil ], [ alert.reload.mailed_at, alert.digest_failures, alert.digest_failed_at ]
        assert_equal :working, MailSettings.current.state, "a digest that went out clears the failure, as any mail does"
      end
    end
  end

  test "a digest that failed goes at once when another mail made mail working again" do
    with_site_address(SITE) do
      with_mail_state(:working) do
        alert = make
        alert.update_columns(digest_failures: 1, digest_failed_at: NOW - 1.minute)
        assert_emails(2) { assert_equal 2, deliver }
        assert_equal [ NOW, 0 ], [ alert.reload.mailed_at, alert.digest_failures ]
      end
    end
  end

  test "a failed reminder keeps the earlier mail's time, so it is neither lost nor marked twice" do
    with_site_address(SITE) do
      with_mail_state(:failed, **refused) do
        reminded = make(seen: NOW - 3.hours, mailed: NOW - 2.hours)
        reminded.update_columns(last_seen_at: NOW - 1.minute)
        fresh = make
        capture_log { assert_equal 0, deliver }

        assert_equal NOW - 2.hours, reminded.reload.mailed_at
        assert_nil fresh.reload.mailed_at
        assert_equal [ 1, 1 ], [ reminded.digest_failures, fresh.digest_failures ]
        assert_equal 2, Alerts::Alert.due(NOW).count, "both are still due"
      end
    end
  end

  test "a send that raises before the delivery gives the alerts back and raises" do
    with_site_address(SITE) do
      with_mail_state(:working) do
        alert = make
        with_singleton_override(Alerts::DigestMailer, :digest, ->(*) { raise NoMethodError, "a bug" }) do
          assert_raises(NoMethodError) { deliver }
        end
        assert_nil alert.reload.mailed_at
        assert_equal 1, alert.digest_failures
      end
    end
  end

  test "with mail saved but not tested the alerts wait, unmarked and untried" do
    with_site_address(SITE) do
      with_mail_state(:untested) do
        alert = make
        capture_log { assert_no_emails { assert_equal 0, deliver } }
        assert_equal [ nil, 0, nil ], [ alert.reload.mailed_at, alert.digest_failures, alert.digest_failed_at ]
      end
    end
  end

  test "with nothing due nothing is logged, even with mail not ready" do
    with_mail_state(:not_set_up) do
      assert_empty capture_log { assert_equal 0, deliver }.lines.grep(/ContentSpiel/)
    end
  end

  test "with no owner nothing is queued and nothing is marked" do
    User.owners.update_all(owner: false) # version: none (a test's setup)
    with_mail_state(:working) do
      with_site_address(SITE) do
        alert = make
        assert_no_emails { assert_equal 0, deliver }
        assert_nil alert.reload.mailed_at
      end
    end
  end

  test "the mark takes only alerts still due: a second mark of the same ids takes none" do
    older = make(seen: NOW - 5.minutes)
    newer = make
    ids = [ newer.id, older.id ]

    assert_equal ids, Alerts::Mailing.new(now: NOW).send(:claim, ids)
    assert_equal [], Alerts::Mailing.new(now: NOW + 1.second).send(:claim, ids)
    assert_equal [ NOW ], [ older, newer ].map { it.reload.mailed_at }.uniq
  end

  test "two runs at once, the second finishing before the first marks, send one mail per owner" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        make
        first = Alerts::Mailing.new(now: NOW)
        pending = first.send(:pending_ids)
        first.define_singleton_method(:pending_ids) do
          Alerts::Mailing.new(now: NOW + 1.second).deliver
          pending
        end

        assert_emails(@owners.size) { assert_equal 0, first.deliver }
        assert_equal @owners.map(&:email_address).sort, sent_to.sort
      end
    end
  end
end
