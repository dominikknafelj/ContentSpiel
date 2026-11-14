require "test_helper"

# The boot's index check (spec §6.6): a process that serves requests
# enqueues `SiteSearch::IndexCheckJob` once the application has booted, and
# nothing else does. A boot never fails because of search.
class SiteSearchBootCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include LogCapture

  test "a console, a rake task and the test environment enqueue no check" do
    assert_not SiteSearch::BootCheck.serving?(env: "test", console: nil, rake: false)
    assert_not SiteSearch::BootCheck.serving?(env: "production", console: "constant", rake: false)
    assert_not SiteSearch::BootCheck.serving?(env: "production", console: true)
    assert_not SiteSearch::BootCheck.serving?(env: "production", console: nil, rake: true)
    assert SiteSearch::BootCheck.serving?(env: "production", console: nil, rake: false)
    assert SiteSearch::BootCheck.serving?(env: "development", console: nil, rake: false)
    assert_not SiteSearch::BootCheck.serving?, "this process is the test environment"

    clear_enqueued_jobs
    assert_nil SiteSearch::BootCheck.run
    assert_no_enqueued_jobs

    assert_nil SiteSearch::BootCheck.run(serving: true)
    assert_enqueued_with(job: SiteSearch::IndexCheckJob)
  end

  test "a queue without its table, or an enqueue that raises, leaves the boot alone" do
    clear_enqueued_jobs
    with_singleton_override(SiteSearch::BootCheck, :queue_ready?, -> { false }) { assert_nil SiteSearch::BootCheck.run(serving: true) }
    assert_no_enqueued_jobs

    refused = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "postgres://queue@db/secret" }
    logged = capture_log do
      with_singleton_override(SiteSearch::IndexCheckJob, :perform_later, refused) { assert_nil SiteSearch::BootCheck.run(serving: true) }
    end
    assert_match "ActiveRecord::ConnectionNotEstablished", logged
    assert_no_match "secret", logged
  end

  test "the boot names the chosen backend" do
    assert_equal "[ContentSpiel] Search: Postgres (postgres)", SiteSearch::BootCheck.log_line
  end
end
