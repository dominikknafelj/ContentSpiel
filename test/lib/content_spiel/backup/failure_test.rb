require "test_helper"

class ContentSpiel::Backup::FailureTest < ActiveSupport::TestCase
  Failure = ContentSpiel::Backup::Failure

  def classify(tool, exit_status, stderr = "")
    Failure.classify(tool: tool, exit_status: exit_status, stderr: stderr)
  end

  test "the reasons are the fixed five" do
    assert_equal %w[destination_unreachable wrong_password database_unreachable disk_full other], Failure::REASONS
  end

  test "a full disk, from either tool" do
    assert_equal "disk_full", classify(:restic, 1, "write: No space left on device")
    assert_equal "disk_full", classify(:pg_dump, 1, "No space left on device")
  end

  test "restic exit 12 is a wrong password" do
    assert_equal "wrong_password", classify(:restic, 12, "anything")
  end

  test "restic's own words for a wrong password" do
    assert_equal "wrong_password", classify(:restic, 1, "Fatal: wrong password or no key found")
  end

  test "restic exit 10 is an unreachable destination" do
    assert_equal "destination_unreachable", classify(:restic, 10, "anything")
  end

  test "restic's network and access words are an unreachable destination" do
    [ "dial tcp", "no such host", "connection refused", "i/o timeout", "Access Denied",
      "InvalidAccessKeyId", "SignatureDoesNotMatch", "NoSuchBucket", "unable to open config file" ].each do |text|
      assert_equal "destination_unreachable", classify(:restic, 1, "x #{text} y"), text
    end
  end

  test "pg_dump's connection words are an unreachable database" do
    [ "could not connect", "connection to server", "could not translate host name",
      "password authentication failed", "no password supplied" ].each do |text|
      assert_equal "database_unreachable", classify(:pg_dump, 1, "pg_dump: #{text}"), text
    end
  end

  test "stderr that is not clean UTF-8 text is still classified" do
    assert_equal "disk_full", classify(:restic, 1, "\xFF No space left on device".b.force_encoding("UTF-8"))
    assert_equal "other", classify(:restic, 1, nil)
  end

  test "an unknown message is other" do
    assert_equal "other", classify(:restic, 1, "something strange")
    assert_equal "other", classify(:pg_dump, 1, "something strange")
  end
end
