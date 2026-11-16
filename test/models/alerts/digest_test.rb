require "test_helper"

# The digest: which alerts are mailed, to whom, how often, and that nothing
# is marked while no mail can go.
class Alerts::DigestTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  include LogCapture

  SITE = "https://docs.example.org".freeze
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  setup do
    Alerts::Alert.delete_all
    travel_to NOW
    @owners = [ users(:one), users(:reader).tap { it.update_columns(owner: true) } ]
  end

  def make(seen: NOW - 1.minute, mailed: nil, kind: "error")
    Alerts::Alert.create!(kind: kind, fingerprint: SecureRandom.hex(8), details: { "error_class" => "RuntimeError", "place" => nil },
                          first_seen_at: seen, last_seen_at: seen, mailed_at: mailed)
  end

  def deliver(now: Time.current) = Alerts::Digest.new(now: now).deliver

  def queued = { fingerprint: MailSettings.current.fingerprint }

  test "two due alerts and two owners: one mail each, and both alerts are marked mailed now" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        older = make(seen: NOW - 5.minutes)
        newer = make(seen: NOW - 1.minute)
        ids = [ newer.id, older.id ]

        assert_enqueued_email_with Alerts::DigestMailer, :digest, params: queued, args: [ @owners.first, ids ] do
          assert_enqueued_email_with Alerts::DigestMailer, :digest, params: queued, args: [ @owners.last, ids ] do
            assert_equal 2, deliver
          end
        end
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
        assert_no_enqueued_emails { assert_equal 0, deliver }

        travel 1.minute
        assert_enqueued_emails(2) { assert_equal 2, deliver }
      end
    end
  end

  test "an alert seen again is mailed again an hour after its mail, not before" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        alert = make(seen: NOW - 70.minutes, mailed: NOW - 59.minutes)
        alert.update_columns(last_seen_at: NOW - 1.minute)
        assert_no_enqueued_emails { assert_equal 0, deliver }

        travel 2.minutes
        assert_enqueued_emails(2) { assert_equal 2, deliver }
        assert_equal Time.current, alert.reload.mailed_at
      end
    end
  end

  test "an alert mailed and not seen since is not mailed again" do
    with_mail_state(:working) do
      with_site_address(SITE) do
        make(seen: NOW - 3.hours, mailed: NOW - 2.hours)
        assert_no_enqueued_emails { assert_equal 0, deliver }
      end
    end
  end

  test "with mail not ready nothing is queued or marked, and one line naming nobody is logged once an hour" do
    with_mail_state(:not_set_up) do
      with_site_address(SITE) do
        alert = make
        log = capture_log do
          assert_no_enqueued_emails { assert_equal 0, deliver }
          travel 30.minutes
          assert_no_enqueued_emails { assert_equal 0, deliver }
        end

        assert_nil alert.reload.mailed_at
        assert_equal [ Alerts::Digest::NOT_READY ], log.lines.map(&:strip).grep(/ContentSpiel/)
        @owners.each { assert_not_includes log, it.email_address }

        travel 31.minutes
        assert_equal [ Alerts::Digest::NOT_READY ], capture_log { deliver }.lines.map(&:strip).grep(/ContentSpiel/)
      end
    end
  end

  test "with no address to link to nothing is queued or marked" do
    with_mail_state(:working) do
      with_site_address(nil) do
        alert = make
        log = capture_log do
          assert_no_enqueued_emails { assert_equal 0, deliver }
        end

        assert_nil alert.reload.mailed_at
        assert_equal [ Alerts::Digest::NO_ADDRESS ], log.lines.map(&:strip).grep(/ContentSpiel/)
      end
    end
  end

  test "with nothing due nothing is logged, even with mail not ready" do
    with_mail_state(:not_set_up) do
      assert_empty capture_log { assert_equal 0, deliver }.lines.grep(/ContentSpiel/)
    end
  end
end
