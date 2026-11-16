require "test_helper"

# The check job: the scan, the digest and the prune in one run, each step on
# its own, so one that fails stops neither of the others.
class Alerts::CheckJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  SITE = "https://docs.example.org".freeze

  setup do
    Alerts::Alert.delete_all
    @old = Alerts::Alert.create!(kind: "error", fingerprint: "old", details: { "error_class" => "RuntimeError", "place" => nil },
                                 first_seen_at: 31.days.ago, last_seen_at: 31.days.ago, mailed_at: 31.days.ago)
  end

  def owner_change
    Audit::Event.create!(action: "user.owner_changed", channel: "web", occurred_at: 2.minutes.ago, last_occurred_at: 2.minutes.ago,
                         subject_label: "Pat", field_changes: { "owner" => [ false, true ] })
  end

  test "one run turns an owner change into an alert, mails it and deletes an alert a month old" do
    owner_change

    with_mail_state(:working) do
      with_site_address(SITE) do
        assert_enqueued_emails(User.owners.count) { Alerts::CheckJob.perform_now }
      end
    end

    alert = Alerts::Alert.sole
    assert_equal "owner_changed", alert.kind
    assert_not_nil alert.mailed_at
    assert_not Alerts::Alert.exists?(@old.id)
  end

  test "a failing scan is reported and logged by its class, and the digest and the prune still run" do
    Alerts::Alert.create!(kind: "error", fingerprint: "due", details: { "error_class" => "RuntimeError", "place" => nil },
                          first_seen_at: 1.minute.ago, last_seen_at: 1.minute.ago)
    failing = Class.new { def apply = raise(RuntimeError, "password=hunter2") }.new

    with_mail_state(:working) do
      with_site_address(SITE) do
        with_singleton_override(Alerts::Rules, :new, ->(**) { failing }) do
          log = capture_log do
            assert_error_reported(RuntimeError) do
              assert_enqueued_emails(User.owners.count) { Alerts::CheckJob.perform_now }
            end
          end

          assert_equal [ "[ContentSpiel] Alert check failed at rules: RuntimeError" ], log.lines.map(&:strip).grep(/ContentSpiel/)
          assert_no_match "hunter2", log
        end
      end
    end

    assert_not_nil Alerts::Alert.find_by(fingerprint: "due").mailed_at
    assert_not Alerts::Alert.exists?(@old.id)
  end

  test "a failing digest still lets the prune run" do
    with_singleton_override(Alerts::Mailing, :new, ->(**) { raise ActiveRecord::ConnectionNotEstablished }) do
      assert_error_reported(ActiveRecord::ConnectionNotEstablished) { Alerts::CheckJob.perform_now }
    end

    assert_not Alerts::Alert.exists?(@old.id)
  end

  test "with error alerts on, a failing step's report becomes no alert of its own" do
    failing = Class.new { def apply = raise(RuntimeError, "scan failed") }.new

    with_error_alerts do
      with_singleton_override(Alerts::Rules, :new, ->(**) { failing }) do
        Alerts::CheckJob.perform_now
      end
    end

    assert_no_enqueued_jobs only: Alerts::RecordErrorJob
  end
end
