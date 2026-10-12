require "test_helper"

# Probes are injected rather than stubbed: Minitest 6 ships no `stub`, and the
# real probes touch the disk, libvips and Solid Queue.
class Setup::SystemCheckTest < ActiveSupport::TestCase
  test "reports every check, in order" do
    labels = run_check.map(&:label)

    assert_equal [ "Site address", "Theme", "File storage", "Image processing", "Background jobs", "Outgoing mail" ], labels
  end

  test "in production with the request's facts, HTTPS comes second" do
    labels = run_check(production: true, request_ssl: true).map(&:label)

    assert_equal [ "Site address", "HTTPS", "Theme", "File storage", "Image processing", "Background jobs", "Outgoing mail" ], labels
  end

  test "a configured site address is named by its origin" do
    check = result("Site address", run_check(address: SiteAddress.parse("https://www.example.org/")))

    assert check.ok?
    assert_equal "This site answers at https://www.example.org.", check.message
    assert_nil check.command
  end

  test "no site address is a warning that says what follows from it, with the variable to set" do
    check = result("Site address", run_check(address: SiteAddress.parse(nil), reset_link_from_request: false))

    assert_equal :warning, check.status
    assert_equal "No site address is set. Any host name is accepted, addresses in pages follow the request, " \
      "and password reset mails are not sent until it is set.", check.message
    assert_equal "PUBLIC_HOST=https://www.example.org", check.command
  end

  # Development and test: the reset mail IS sent there, with the request's
  # origin in its link (`PasswordsMailer.request_origin_used?`), so the
  # sentence that it is not would be false.
  test "where a reset mail takes its link from the request, the warning says that and not that none is sent" do
    check = result("Site address", run_check(address: SiteAddress.parse(nil), reset_link_from_request: true))

    assert_equal :warning, check.status
    # No word of which hosts are accepted: test answers any, development keeps
    # Rails' own list (localhost, .test, IP addresses).
    assert_equal "No site address is set. Addresses in pages and in password reset mails follow the request.", check.message
    assert_equal "PUBLIC_HOST=https://www.example.org", check.command
  end

  test "nobody having said, the warning is the one that fails closed: reset mails are not sent" do
    check = result("Site address", Setup::SystemCheck.run(address: SiteAddress.parse(nil)))

    assert_includes check.message, "password reset mails are not sent until it is set"
  end

  test "a configured address reads the same wherever the reset link comes from" do
    [ true, false ].each do |from_request|
      check = result("Site address", run_check(reset_link_from_request: from_request))

      assert_equal "This site answers at https://cms.example.org.", check.message
    end
  end

  # A proxy ends TLS and the address still says http: the pages' canonical
  # links, the sitemap and the reset mail carry http, no cookie is Secure and
  # no HSTS is sent, while the HTTPS row beside this one says OK.
  test "an http address reached over HTTPS is a warning that says which to change, and names the address" do
    check = result("Site address", run_check(address: SiteAddress.parse("http://docs.example.org"), request_ssl: true))

    assert_equal :warning, check.status
    assert_equal "This site answers at http://docs.example.org. The address is http but this page was reached over HTTPS: " \
      "set PUBLIC_HOST to the https address.", check.message
    assert_equal "PUBLIC_HOST=https://www.example.org", check.command
  end

  test "the address is OK as it is when it is https, when the page came over plain HTTP, and when nobody said how it came" do
    [ [ "https://docs.example.org", true ], [ "https://docs.example.org", false ],
      [ "http://docs.example.org", false ], [ "http://docs.example.org", nil ] ].each do |address, request_ssl|
      check = result("Site address", run_check(address: SiteAddress.parse(address), request_ssl: request_ssl))

      assert check.ok?, [ address, request_ssl ].inspect
      assert_equal "This site answers at #{address}.", check.message
      assert_nil check.command
    end
  end

  test "the address defaults to the site's own" do
    with_site_address("https://docs.example.org") do
      assert_equal "This site answers at https://docs.example.org.", result("Site address", Setup::SystemCheck.run).message
    end
    with_site_address(nil) do
      assert_equal :warning, result("Site address", Setup::SystemCheck.run).status
    end
  end

  test "HTTPS in production: an encrypted request is ok" do
    check = result("HTTPS", run_check(production: true, request_ssl: true))

    assert check.ok?
    assert_equal "This page was reached over an encrypted connection.", check.message
  end

  test "HTTPS in production: a plain request is a warning that says what to set" do
    check = result("HTTPS", run_check(production: true, request_ssl: false))

    assert_equal :warning, check.status
    assert_equal "This page was reached over plain HTTP. Passwords and sessions can be read on the way. " \
      "Set PUBLIC_HOST to an https address.", check.message
    assert_nil check.command
  end

  test "HTTPS is left out when nobody said how the page was reached, and outside production" do
    assert_nil result("HTTPS", run_check(production: true, request_ssl: nil))
    assert_nil result("HTTPS", run_check(production: true))
    assert_nil result("HTTPS", run_check(production: false, request_ssl: false))
    assert_nil result("HTTPS", run_check(production: false, request_ssl: true))
    # The default is the environment's, and the tests do not run in production.
    assert_nil result("HTTPS", Setup::SystemCheck.run(request_ssl: false))
  end

  test "without a theme folder the row says the default theme draws the site" do
    check = result("Theme", run_check(theme: Theme.new))

    assert check.ok?
    assert_equal "The default theme draws the site (THEME_PATH is not set).", check.message
    assert_nil check.command
  end

  test "with a theme folder the row names it, its templates and the start of its fingerprint, and not its path" do
    theme = Theme.load(ThemeFolder.new(ThemeTestHelper::PLAIN))
    check = result("Theme", run_check(theme: theme))

    assert check.ok?
    assert_equal "The theme “plain” draws the site (#{theme.template_count} templates, fingerprint #{theme.fingerprint[0, 8]}).", check.message
    assert_not_includes check.message, ThemeTestHelper::PLAIN.dirname.to_s
  end

  test "in production a stylesheet built for another theme is a warning that says to build again" do
    theme = Theme.load(ThemeFolder.new(ThemeTestHelper::PLAIN))
    check = result("Theme", run_check(theme: theme, production: true, request_ssl: true, stylesheet_probe: -> { false }))

    assert_equal :warning, check.status
    assert_equal "The theme “plain” is set, but the stylesheet was built for another theme, so the site is drawn with the wrong styles. " \
      "Build the site's image again: assets:precompile with THEME_PATH set.", check.message
    assert_nil check.command
  end

  test "in production the default theme under a stylesheet built with a theme is the same warning, the other way round" do
    check = result("Theme", run_check(theme: Theme.new, production: true, request_ssl: true, stylesheet_probe: -> { false }))

    assert_equal :warning, check.status
    assert_equal "The default theme is set, but the stylesheet was built for another theme, so the site is drawn with the wrong styles. " \
      "Build the site's image again: assets:precompile without THEME_PATH.", check.message
  end

  # Outside production no boot refuses a stylesheet built for another theme
  # (a development server starts under anything), so this row is the one
  # place that says it, with the command that builds it.
  test "outside production a stylesheet built for another theme is a warning with the command that builds it" do
    theme = Theme.load(ThemeFolder.new(ThemeTestHelper::PLAIN))
    check = result("Theme", run_check(theme: theme, production: false, stylesheet_probe: -> { false }))

    assert_equal :warning, check.status
    assert_equal "The theme “plain” is set, but the stylesheet was built for another theme or for an earlier state of this one, " \
      "so the site is drawn with the wrong styles. A test run does that, also while bin/dev runs: it builds the default " \
      "theme's stylesheet into the same place. Build the theme's again with THEME_PATH set as the server has it: " \
      "run this command, or start bin/dev again.", check.message
    assert_equal "bin/rails tailwindcss:build", check.command
    assert Setup::SystemCheck::STYLESHEET_COMMAND.frozen?

    default = result("Theme", run_check(theme: Theme.new, production: false, stylesheet_probe: -> { false }))
    assert_equal :warning, default.status
    assert_includes default.message, "The default theme is set, but the stylesheet was built for another theme"
    assert_equal "The default theme is set, but the stylesheet was built for another theme, so the site is drawn with the wrong " \
      "styles. Build it again without THEME_PATH: run this command, or start bin/dev again.", default.message
    assert_no_match(/keeps it built/, check.message + default.message)
  end

  # R3 of the re-review. A build takes the stamp away before it starts and
  # writes it after it succeeded (`ThemeCss.build`), and a fresh checkout
  # has none: with no stamp nothing "was built for another theme". The probe
  # answers nil for that, and the row says what is so, with the same command.
  test "with no stamp at all the row says the stylesheet was not built or its build failed, for either theme, with the command" do
    default = result("Theme", run_check(theme: Theme.new, production: false, stylesheet_probe: -> { nil }))

    assert_equal :warning, default.status
    assert_equal "The default theme is set, but the public stylesheet has not been built, or its last build failed, so the site " \
      "is drawn with an earlier build's styles or with none. Build it without THEME_PATH: run this command, or start bin/dev " \
      "again. If the build fails, it says why where it runs.", default.message
    assert_equal "bin/rails tailwindcss:build", default.command
    assert_no_match(/another theme/, default.message)

    theme = Theme.load(ThemeFolder.new(ThemeTestHelper::PLAIN))
    themed = result("Theme", run_check(theme: theme, production: false, stylesheet_probe: -> { nil }))

    assert_equal "The theme “plain” is set, but the public stylesheet has not been built, or its last build failed, so the site " \
      "is drawn with an earlier build's styles or with none. Build it with THEME_PATH set as the server has it: run this " \
      "command, or start bin/dev again. If the build fails, it says why where it runs.", themed.message
    assert_equal "bin/rails tailwindcss:build", themed.command

    production = result("Theme", run_check(theme: theme, production: true, request_ssl: true, stylesheet_probe: -> { nil }))
    assert_equal "The theme “plain” is set, but the public stylesheet has not been built, or its last build failed, so the site " \
      "is drawn with an earlier build's styles or with none. Build the site's image again: assets:precompile with THEME_PATH set.",
      production.message
    assert_nil production.command
  end

  test "the row's own probe tells no stamp from another theme's" do
    Dir.mktmpdir("root") do |root|
      probe = Setup::SystemCheck.stylesheet_probe(Theme.new, root: root)
      assert_nil probe.call, "no stamp"

      ThemeCss.stamp!(ThemeFolder.new(nil), root: root)
      assert_equal true, probe.call

      ThemeCss.stamp!(ThemeFolder.new(ThemeTestHelper::PLAIN), root: root)
      assert_equal false, probe.call, "another theme's"
    end
  end

  test "a probe that raises is a stylesheet that was not built for the theme, and never a path" do
    check = result("Theme", run_check(theme: Theme.new, stylesheet_probe: -> { raise Errno::EACCES, "/rails/app/assets/builds/theme.stamp" }))

    assert_equal :warning, check.status
    assert_not_includes check.message, "/rails"
  end

  test "the row's own probe reads the build's stamp: this suite's stylesheet is the default theme's" do
    assert_equal "default", ThemeFolder.stamp(Rails.root), "bin/rails tailwindcss:build stamps the stylesheet the tests read"
    assert result("Theme", Setup::SystemCheck.run(theme: Theme.new)).ok?

    theme = Theme.load(ThemeFolder.new(ThemeTestHelper::PLAIN))
    assert_equal :warning, result("Theme", Setup::SystemCheck.run(theme: theme)).status
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

  # Production's mailed links take their host from the site's address
  # (`HostSettings.apply`), so with none set a mail server that is perfectly
  # set up still counts as "not configured". The warning says which half is
  # missing instead of sending the reader to their SMTP settings.
  test "a mail server without a site address: the warning names the address as what is missing" do
    check = result("Outgoing mail", run_check(address: SiteAddress.parse(nil), mail_host: "", reset_link_from_request: false))

    assert_equal :warning, check.status
    assert_equal "A mail server is set, but no site address is, and without one no password reset mail is sent: set PUBLIC_HOST. " +
      Setup::SystemCheck::MAIL_FALLBACK_MESSAGE, check.message
    assert_equal Setup::SystemCheck::MAIL_FALLBACK_COMMAND, check.command
  end

  test "the address is not named where it is not the cause: no mail server, a link from the request, an address that is set" do
    no_server = run_check(address: SiteAddress.parse(nil), mail_host: "", mail_smtp_address: "localhost", reset_link_from_request: false)
    local = run_check(address: SiteAddress.parse(nil), mail_host: "", reset_link_from_request: true)
    with_address = run_check(mail_host: "example.com", reset_link_from_request: false)

    [ no_server, local, with_address ].each do |results|
      assert_equal Setup::SystemCheck::MAIL_FALLBACK_MESSAGE, result("Outgoing mail", results).message
    end
    # And with the request's origin for the link, a mail server and a host for it are all it takes.
    assert result("Outgoing mail", run_check(address: SiteAddress.parse(nil), mail_host: "localhost", reset_link_from_request: true)).ok?
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

  # A command is shown to anyone who may view the status page and, in the
  # wizard, before anyone is signed in: each is a fixed string.
  test "only the site address and the mail warnings carry a command, each a fixed string" do
    results = run_check(address: SiteAddress.parse(nil), production: true, request_ssl: false,
      storage_probe: -> { false }, image_probe: -> { false }, queue_adapter: "solid_queue", worker_alive_probe: -> { false },
      mail_host: "example.com", stylesheet_probe: -> { false })

    # Every row that can warn does. The theme's carries no command in
    # production, where the build is the image's and no one command.
    assert results.none?(&:ok?)
    assert_equal({ "Site address" => Setup::SystemCheck::SITE_ADDRESS_COMMAND, "Outgoing mail" => Setup::SystemCheck::MAIL_FALLBACK_COMMAND },
      results.select(&:command).to_h { |check| [ check.label, check.command ] })
    assert Setup::SystemCheck::SITE_ADDRESS_COMMAND.frozen?
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
        mail_host: "cms.example.org", address: SiteAddress.parse("https://cms.example.org"), stylesheet_probe: -> { true }
      }
      Setup::SystemCheck.run(**defaults.merge(overrides))
    end

    def result(label, results) = results.find { |r| r.label == label }
end
