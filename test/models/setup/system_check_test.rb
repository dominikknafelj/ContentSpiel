require "test_helper"

# Probes are injected rather than stubbed: Minitest 6 ships no `stub`, and the
# real probes touch the disk, libvips and Solid Queue.
class Setup::SystemCheckTest < ActiveSupport::TestCase
  test "reports every check, in order" do
    labels = run_check.map(&:label)

    assert_equal [ "File storage", "Image processing", "Background jobs", "Outgoing mail" ], labels
  end

  test "the real storage probe works against the test disk service" do
    assert_no_difference "ActiveStorage::Blob.count" do
      assert result("File storage", Setup::SystemCheck.run).ok?
    end
  end

  test "a storage failure is a warning, not an exception" do
    check = result("File storage", run_check(storage_probe: -> { raise Errno::EACCES }))

    assert_equal :warning, check.status
    assert_includes check.message, "writable"
  end

  test "a missing libvips is a warning" do
    check = result("Image processing", run_check(image_probe: -> { raise LoadError }))

    assert_equal :warning, check.status
    assert_includes check.message, "libvips"
  end

  test "jobs are fine when an in-process adapter runs them" do
    assert result("Background jobs", run_check(queue_adapter: "async")).ok?
  end

  test "Solid Queue without a recent worker heartbeat is a warning" do
    check = result("Background jobs", run_check(queue_adapter: "solid_queue", worker_alive_probe: -> { false }))

    assert_equal :warning, check.status
    assert_includes check.message, "SOLID_QUEUE_IN_PUMA"
  end

  test "Solid Queue with a live worker is ok" do
    assert result("Background jobs", run_check(queue_adapter: "solid_queue", worker_alive_probe: -> { true })).ok?
  end

  test "unconfigured mail is a warning with a copyable command for the console fallback" do
    check = result("Outgoing mail", run_check(mail_host: "example.com"))

    assert_equal :warning, check.status
    # The message is the command's instructions (final fix wave): what to
    # replace, the one thing a pasted password must not contain, and what the
    # printed `true`/`false` mean -- a bare "false" told nobody anything.
    assert_equal Setup::SystemCheck::MAIL_FALLBACK_MESSAGE, check.message
    assert_equal "Password reset by email isn't configured. To set a password from the server instead, run this command with the account's email address, " \
      "replacing “a new password” in both places with the new one (at least 12 characters, with no quotes in it). " \
      "It prints true when the password was changed, and false when it was refused (too short, or the two don't match).", check.message
    # Static text with a placeholder address and password: it is shown to
    # anyone who may view the status page, so it never carries a real value.
    assert_equal Setup::SystemCheck::MAIL_FALLBACK_COMMAND, check.command
    assert_match(/\Abin\/rails runner '.*Users::UpdatePassword/, check.command)
    assert_nil check.docs
  end

  # The command is a static string, so prove it works: put a real address and
  # password where the placeholders are, run the Ruby inside the quotes (not a
  # subprocess) and look at what it did.
  test "the mail fallback command sets the password, ends every session and is audited" do
    user = users(:reader)
    user.sessions.create!
    user.sessions.create!
    ruby = Setup::SystemCheck::MAIL_FALLBACK_COMMAND[/runner '(.*)'\z/, 1]
      .sub("you@example.com", user.email_address).gsub("a new password", "a brand new pass 1")

    assert_difference -> { Audit::Event.where(action: "user.updated", subject: user).count }, 1 do
      output, = capture_io { assert_equal true, eval(ruby) }
      assert_equal "true\n", output
    end

    assert user.reload.authenticate("a brand new pass 1")
    assert_equal 0, user.sessions.count
  end

  # What the message promises about the command, proved on the command itself.
  test "the mail fallback command prints false, changes nothing and ends no session when the password is refused" do
    user = users(:reader)
    user.sessions.create!
    digest = user.password_digest
    ruby = Setup::SystemCheck::MAIL_FALLBACK_COMMAND[/runner '(.*)'\z/, 1].sub("you@example.com", user.email_address)

    # Too short (the rule the message names).
    output, = capture_io { assert_equal false, eval(ruby.gsub("a new password", "short")) }
    assert_equal "false\n", output
    # Replaced in one place only: the two don't match.
    output, = capture_io { assert_equal false, eval(ruby.sub("a new password", "a brand new pass 1")) }
    assert_equal "false\n", output

    assert_equal digest, user.reload.password_digest
    assert_equal 1, user.sessions.count
    # The placeholder appears exactly twice, and the constant has no value of anyone's.
    assert_equal 2, Setup::SystemCheck::MAIL_FALLBACK_COMMAND.scan("a new password").size
    assert Setup::SystemCheck::MAIL_FALLBACK_COMMAND.frozen?
    assert Setup::SystemCheck::MAIL_FALLBACK_MESSAGE.frozen?
  end

  test "a Result built without a command or docs link has neither" do
    check = Setup::SystemCheck::Result.new(label: "x", status: :ok, message: "fine")

    assert_nil check.command
    assert_nil check.docs
  end

  test "only the mail warning carries a command" do
    commands = run_check(storage_probe: -> { false }, image_probe: -> { false }, mail_host: "example.com").map(&:command)

    assert_equal [ nil, nil, nil ], commands.first(3)
    assert_predicate commands.last, :present?
  end

  test "configured SMTP with a real host is ok" do
    check = result("Outgoing mail",
      run_check(mail_delivery_method: :smtp, mail_smtp_address: "smtp.mailgun.org", mail_host: "cms.example.org"))

    assert check.ok?
  end

  private
    def run_check(**overrides)
      defaults = {
        storage_probe: -> { true }, image_probe: -> { true }, worker_alive_probe: -> { true },
        queue_adapter: "async", mail_delivery_method: :smtp, mail_smtp_address: "smtp.example.org",
        mail_host: "cms.example.org"
      }
      Setup::SystemCheck.run(**defaults.merge(overrides))
    end

    def result(label, results) = results.find { |r| r.label == label }
end
