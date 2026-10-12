require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

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
# Each boot is about three seconds, so there are seven and no more: an https
# address, none, and a value that is no address; and for the theme, a
# folder, a path that is none, a folder with a file the contract does
# not name (`Theme::Check`, run by `Theme.load` in `to_prepare`: the one
# proof that the contract is checked when the application starts), and a
# folder the stylesheet was not built for.
class ProductionBootTest < ActiveSupport::TestCase
  SCRIPT = <<~'RUBY'.freeze
    config = Rails.application.config
    puts "hosts: #{config.hosts.inspect}"
    puts "force_ssl: #{config.force_ssl.inspect}"
    puts "assume_ssl: #{config.assume_ssl.inspect}"
    puts "hsts: #{config.ssl_options[:hsts].inspect}"
    puts "mailer: #{config.action_mailer.default_url_options.inspect}"
    puts "health check excluded: #{[ config.host_authorization[:exclude], config.ssl_options.dig(:redirect, :exclude) ].all? { |rule| rule.equal?(HostSettings::HEALTH_CHECK) }}"
    puts "theme: #{Theme.current.name} #{Theme.current.fingerprint}"
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
    assert_includes lines, "[ContentSpiel] Theme: the default theme (THEME_PATH is not set)"
    assert_includes lines, "theme: default default"
  end

  test "production with a PUBLIC_HOST that is no address does not start, and says which variable without repeating it" do
    printed, status = boot_production("PUBLIC_HOST" => "https://user:hunter2@docs.example.org:port")

    assert_not status.success?, printed
    assert_includes printed, "PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org"
    assert_includes printed, "SiteAddress::Invalid"
    assert_no_match(/hunter2|docs\.example\.org|hosts:/, printed)
  end

  # The theme is a COPY OUTSIDE THE APPLICATION, with an image, a font and a
  # controller in it, because that is what every real site's theme is: a
  # folder beside the application whose own asset folders the boot puts on
  # the load path. Booted from the fixture inside the application, this test
  # was green while no such site started (`Theme::Check.cms_asset_roots`
  # took the theme's own folders for a gem's).
  test "production under a theme folder outside the application says which at boot, and the application's theme is that folder" do
    Dir.mktmpdir("site") do |site|
      plain = Pathname(site).join("plain")
      FileUtils.cp_r(Rails.root.join("test/fixtures/themes/plain"), plain)
      plain.join("assets/fonts").mkpath
      plain.join("assets/fonts/plain-sans.woff2").write("x")
      assert_not plain.to_s.start_with?("#{Rails.root}/")
      assert_equal 3, ThemeFolder.new(plain).asset_paths.size, "an image, a font and a controller"

      printed, status = boot_production("THEME_PATH" => plain.to_s)
      lines = printed.lines(chomp: true)

      assert status.success?, printed
      assert_includes lines, ThemeFolder.announcement(ThemeFolder.new(plain))
      assert_includes lines, "theme: plain #{ThemeFolder.new(plain).fingerprint}"
    end
  end

  test "production with a THEME_PATH that names no folder does not start, and says which variable and which path" do
    printed, status = boot_production("THEME_PATH" => "/no/such/theme/anywhere")

    assert_not status.success?, printed
    assert_includes printed, "THEME_PATH names no directory: /no/such/theme/anywhere"
    assert_includes printed, "ThemeFolder::Invalid"
    assert_no_match(/^hosts:/, printed)
  end

  test "production with a theme folder that holds a file the contract does not name does not start, and names the file" do
    Dir.mktmpdir("theme") do |dir|
      FileUtils.mkdir_p(File.join(dir, "views/pages"))
      File.write(File.join(dir, "views/pages/shwo.html.erb"), "x")

      printed, status = boot_production("THEME_PATH" => dir)

      assert_not status.success?, printed
      assert_includes printed, "ThemeFolder::Invalid"
      assert_includes printed, "views/pages/shwo.html.erb is not part of the theme contract"
      assert_no_match(/^hosts:/, printed)
    end
  end

  # The one boot here with a real secret: with SECRET_KEY_BASE_DUMMY the
  # stylesheet's stamp is not asked, because that is how the image's own
  # `assets:precompile` starts production before the stylesheet exists.
  test "production under a theme whose stylesheet was not built for it does not start, and says how to build" do
    plain = Rails.root.join("test/fixtures/themes/plain")
    printed, status = boot_production("THEME_PATH" => plain.to_s, "SECRET_KEY_BASE_DUMMY" => nil, "SECRET_KEY_BASE" => "x" * 64)

    assert_not status.success?, printed
    assert_includes printed, "ThemeFolder::Invalid"
    assert_includes printed, "the stylesheet was built for another theme: run assets:precompile with THEME_PATH set"
    assert_no_match(/^hosts:/, printed)
  end

  private
    BOOT_SECONDS = 90

    # What the boot printed (stdout and stderr together, the log among it:
    # production logs to STDOUT) and how it ended. Every variable the boot
    # reads is set or taken away here, so the shell's own decide nothing.
    def boot_production(variables)
      env = {
        "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1",
        "PUBLIC_HOST" => nil, "SITEMAP_HOST" => nil, "THEME_PATH" => nil, "ASSUME_SSL" => nil, "RAILS_LOG_LEVEL" => nil,
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
