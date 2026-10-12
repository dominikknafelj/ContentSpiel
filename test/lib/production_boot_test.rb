require "test_helper"
require "open3"

# Production is wired to `HostSettings`, and nothing else in the suite knows:
# every other test of hosts, HTTPS and HSTS hands `HostSettings.apply` a
# config of its own or builds its own middleware stack, so the one line of
# `config/environments/production.rb` that calls it, and the initializer in
# `config/application.rb` that prints the boot's lines, could be deleted with
# every one of them green. The site would then answer any host over plain
# HTTP while its documents say otherwise.
#
# So this boots production for real, as `test/lib/telemetry_exporter_test.rb`
# boots development: `bin/rails runner` in a child process, killed when it
# does not finish. No database is needed (the one read at boot,
# `config/initializers/setup_token.rb`, goes on without an answer), and
# `DATABASE_URL` is taken away so that no database a runner happens to name
# is asked. `SECRET_KEY_BASE_DUMMY=1` is the Dockerfile's own way to boot
# without a secret; the secret check has its tests in `host_settings_test.rb`
# and is not booted for here.
#
# Each boot is about three seconds, so there are three and no more: an https
# address, none, and a value that is no address.
class ProductionBootTest < ActiveSupport::TestCase
  SCRIPT = <<~'RUBY'.freeze
    config = Rails.application.config
    puts "hosts: #{config.hosts.inspect}"
    puts "force_ssl: #{config.force_ssl.inspect}"
    puts "assume_ssl: #{config.assume_ssl.inspect}"
    puts "hsts: #{config.ssl_options[:hsts].inspect}"
    puts "mailer: #{config.action_mailer.default_url_options.inspect}"
    puts "health check excluded: #{[ config.host_authorization[:exclude], config.ssl_options.dig(:redirect, :exclude) ].all? { |rule| rule.equal?(HostSettings::HEALTH_CHECK) }}"
  RUBY

  test "production with an https address answers that host alone, forces HTTPS, mails the address and says so at boot" do
    printed, status = boot_production("PUBLIC_HOST" => "https://docs.example.org")
    lines = printed.lines(chomp: true)

    assert status.success?, printed
    assert_includes lines, %(hosts: ["docs.example.org"])
    assert_includes lines, "force_ssl: true"
    assert_includes lines, "assume_ssl: false"
    assert_includes lines, "hsts: {expires: 31536000, subdomains: false, preload: false}"
    assert_includes lines, %(mailer: {host: "docs.example.org", protocol: "https"})
    assert_includes lines, "health check excluded: true"
    # The initializer's lines, as `HostSettings.announcement` gives them.
    HostSettings.announcement(SiteAddress.parse("https://docs.example.org"), {}).each do |line|
      assert_includes lines, line
    end
    assert_empty lines.grep(/RAILS_LOG_LEVEL/), "no warning about the log level at info"
  end

  test "production with no address refuses and forces nothing, says so, and warns about a debug log level" do
    printed, status = boot_production("RAILS_LOG_LEVEL" => "debug")
    lines = printed.lines(chomp: true)

    assert status.success?, printed
    assert_includes lines, "hosts: []"
    assert_includes lines, "force_ssl: false"
    assert_includes lines, "mailer: {}"
    assert_includes lines, "[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS."
    assert_includes lines, HostSettings.log_level_warning({ "RAILS_LOG_LEVEL" => "debug" })
  end

  test "production with a PUBLIC_HOST that is no address does not start, and says which variable without repeating it" do
    printed, status = boot_production("PUBLIC_HOST" => "https://user:hunter2@docs.example.org:port")

    assert_not status.success?, printed
    assert_includes printed, "PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org"
    assert_includes printed, "SiteAddress::Invalid"
    assert_no_match(/hunter2|docs\.example\.org|hosts:/, printed)
  end

  private
    BOOT_SECONDS = 90

    # What the boot printed (stdout and stderr together, the log among it:
    # production logs to STDOUT) and how it ended. Every variable the boot
    # reads is set or taken away here, so the shell's own decide nothing.
    def boot_production(variables)
      env = {
        "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1",
        "PUBLIC_HOST" => nil, "SITEMAP_HOST" => nil, "ASSUME_SSL" => nil, "RAILS_LOG_LEVEL" => nil,
        "SECRET_KEY_BASE" => nil, "RAILS_MASTER_KEY" => nil, "DATABASE_URL" => nil, "ADMIN_PATH" => nil,
        "OTEL_EXPORTER_OTLP_ENDPOINT" => nil, "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => nil, "OTEL_CONSOLE" => nil
      }.merge(variables)

      Bundler.with_original_env do
        Open3.popen2e(env, Rails.root.join("bin/rails").to_s, "runner", SCRIPT, chdir: Rails.root.to_s) do |input, output, thread|
          input.close
          reader = Thread.new { output.read }

          unless thread.join(BOOT_SECONDS)
            Process.kill("KILL", thread.pid)
            thread.join
            flunk "the production boot did not finish in #{BOOT_SECONDS} seconds"
          end

          [ reader.value, thread.value ]
        end
      end
    end
end
