require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"
require Rails.root.join("lib/content_spiel/site_generator").to_s

# `contentspiel new NAME` (bin/contentspiel), whose work is
# `ContentSpiel::SiteGenerator`: a site folder that builds on a release.
# Written into a throwaway folder; the entrypoint itself is run as the image
# runs it, a plain `ruby bin/contentspiel`, for what it answers without
# starting the application.
class SiteGeneratorTest < ActiveSupport::TestCase
  ENTRYPOINT = Rails.root.join("bin/contentspiel").to_s

  # Everything `new` writes beside the theme, and nothing else.
  SITE_FILES = %w[
    .contentspiel-version
    .dockerignore
    .gitignore
    .kamal/secrets.example
    Dockerfile
    README.md
    config/deploy.yml
    config/postgres/10-contentspiel-databases.sh
    seeds/README.md
  ].freeze

  test "the folder holds exactly the site's files, and theme/ is what theme:new writes" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write

      reference = File.join(dir, "reference")
      Theme::Scaffold.write(reference)
      theme_files = files_under(reference).map { |file| "theme/#{file}" }

      assert_equal (SITE_FILES + theme_files).sort, files_under(site).sort
      files_under(reference).each do |file|
        assert_equal File.read(File.join(reference, file)), File.read(File.join(site, "theme", file)), "theme/#{file}"
      end
    end
  end

  test "the pin is this CMS's VERSION, and the Dockerfile and deploy.yml read it from there" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write

      assert_equal "#{ContentSpiel::VERSION}\n", File.read(File.join(site, ".contentspiel-version"))

      dockerfile = File.read(File.join(site, "Dockerfile"))
      assert_includes dockerfile, "# check=skip=InvalidDefaultArgInFrom"
      assert_match(/^ARG CMS_IMAGE=#{Regexp.escape(ContentSpiel::IMAGE)}$/, dockerfile)
      assert_match(/^ARG CMS_VERSION$/, dockerfile, "no default on purpose")
      assert_match(/^FROM \$\{CMS_IMAGE\}:\$\{CMS_VERSION\}$/, dockerfile)
      assert_match(/^COPY --chown=1000:1000 theme\/ \/rails\/site-theme\/$/, dockerfile)
      assert_operator dockerfile.index("theme:check"), :<, dockerfile.index("assets:precompile"), "the check goes first"

      deploy = File.read(File.join(site, "config/deploy.yml"))
      assert_includes deploy, %(pin = File.exist?(".contentspiel-version") ? File.read(".contentspiel-version").strip : "")
      assert_includes deploy, %(CMS_VERSION: <%= pin %>)
      assert_equal ContentSpiel::VERSION, kamal_config(site).dig("builder", "args", "CMS_VERSION")
      assert_includes deploy, "service: my-site"
      assert_includes deploy, "PGHOST: my-site-db"
      assert_no_match(/CMS_REVISION|CMS_TAG/, deploy)
    end
  end

  test "deploy.yml names every variable production reads, and the README lists every placeholder" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      deploy = File.read(File.join(site, "config/deploy.yml"))
      readme = File.read(File.join(site, "README.md"))
      secrets = File.read(File.join(site, ".kamal/secrets.example"))

      %w[PUBLIC_HOST ASSUME_SSL THEME_PATH SECRET_KEY_BASE SETUP_TOKEN
         OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_TRACES_ENDPOINT OTEL_CONSOLE
         MAIL_SMTP_SERVER MAIL_SMTP_PORT MAIL_SMTP_SECURITY MAIL_SMTP_USERNAME MAIL_SMTP_PASSWORD
         MAIL_SENDER_NAME MAIL_SENDER_ADDRESS SOLID_QUEUE_IN_PUMA PGHOST CONTENT_SPIEL_DATABASE_PASSWORD
         ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
         ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT TRUSTED_PROXIES
         TURNSTILE_SITE_KEY TURNSTILE_SECRET_KEY LEAKED_PASSWORD_CHECK forward_headers].each do |name|
        assert_includes deploy, name
      end

      # Every secret deploy.yml names (the site's, the registry's, the
      # database's) has its line in the example, and the example names
      # nothing else.
      config = kamal_config(site)
      listed = config.dig("env", "secret") + config.dig("registry", "password") + config.dig("accessories", "db", "env", "secret")
      assert_equal listed.map { |key| key.split(":").first }.uniq.sort, example_names(secrets).sort
      assert_includes example_names(secrets), "POSTGRES_PASSWORD"

      placeholders = deploy.scan(/<your-[a-z-]+>/).uniq
      assert_operator placeholders.size, :>=, 3
      placeholders.each { |placeholder| assert_includes readme, "`#{placeholder}`" }
      %w[contentspiel\ dev contentspiel\ check kamal\ setup kamal\ deploy contentspiel\ upgrade].each do |command|
        assert_includes readme, command
      end
    end
  end

  test "no file holds a secret-looking value" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write

      files_under(site).each do |file|
        text = File.read(File.join(site, file))
        assert_no_match(/\b\h{32,}\b/, text, "#{file}: a long hex string")
        assert_no_match(/\b(ghp_|gho_|github_pat_|glpat-|sk-|xox[bp]-|AKIA)[A-Za-z0-9]/, text, "#{file}: a token's prefix")
        assert_no_match(/-----BEGIN [A-Z ]*PRIVATE KEY-----/, text, "#{file}: a private key")
      end

      # The example's every line is a comment or NAME=$NAME: a name, never a value.
      File.read(File.join(site, ".kamal/secrets.example")).lines.grep_v(/\A\s*(#|\z)/).each do |line|
        assert_match(/\A([A-Z0-9_]+)=\$\1\n?\z/, line)
      end
      # And no secret is given a value in deploy.yml, commented or not: they
      # are listed by name. The names are the example's own, the optional
      # ones it lists in comments included.
      secrets = File.read(File.join(site, ".kamal/secrets.example"))
      optional = secrets.scan(/^#\s+([A-Z][A-Z0-9_]+)\s{2,}/).flatten
      assert_includes optional, "OTEL_EXPORTER_OTLP_HEADERS"
      deploy = File.read(File.join(site, "config/deploy.yml"))
      (example_names(secrets) + optional).each do |key|
        assert_no_match(/^[\s#]*#{key}:/, deploy, "#{key} is given a value in deploy.yml")
      end
    end
  end

  test "README's grep for placeholders finds none once they are filled, and the guard line is not one" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      readme = File.read(File.join(site, "README.md"))
      assert_includes readme, "grep -nE '<your-[a-z-]+>' config/deploy.yml"

      pattern = /<your-[a-z-]+>/ # the README's, as grep -E reads it
      filled = File.read(File.join(site, "config/deploy.yml")).gsub(pattern, "filled")
      assert_empty filled.lines.grep(pattern)
    end
  end

  test "Postgres runs as its own superuser, and the init script makes the site's role and the four databases" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      db = kamal_config(site).dig("accessories", "db")
      assert_equal "postgres", db.dig("env", "clear", "POSTGRES_USER")
      assert_equal %w[POSTGRES_PASSWORD CONTENT_SPIEL_DATABASE_PASSWORD], db.dig("env", "secret")
      assert_equal [ "config/postgres/10-contentspiel-databases.sh:/docker-entrypoint-initdb.d/10-contentspiel-databases.sh" ], db["files"]

      script = File.join(site, "config/postgres/10-contentspiel-databases.sh")
      assert File.executable?(script)
      production = Rails.application.config.database_configuration.fetch("production")
      assert_equal production.values.map { |config| config.fetch("database") }.sort,
                   File.read(script).scan(/CREATE DATABASE (\S+)/).flatten.sort
      assert_includes File.read(script), "CREATE ROLE #{production.fetch("primary").fetch("username")} LOGIN"
    end
  end

  test "the .dockerignore lets the theme into the build and nothing else" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      lines = File.read(File.join(site, ".dockerignore")).lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      assert_equal [ "*", "!theme/" ], lines
    end
  end

  test "a scaffold that fails halfway leaves nothing behind" do
    in_tmp do |dir|
      failing = ->(*) { raise Theme::Scaffold::Refused, "no" }
      with_singleton_override(Theme::Scaffold, :write, failing) do
        assert_raises(Theme::Scaffold::Refused) { ContentSpiel::SiteGenerator.new(File.join(dir, "my-site")).write }
      end
      assert_empty Dir.children(dir)
    end
  end

  test "the site folder is an ordinary folder, not mktmpdir's 0700" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      assert_equal 0o777 & ~File.umask, File.stat(site).mode & 0o777
    end
  end

  test "the generated theme passes Theme::Check" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      assert_empty Theme::Check.problems(ThemeFolder.new(File.join(site, "theme")), deep: true)
    end
  end

  test "the .gitignore keeps the secrets, the env files and the dev folder out" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      ignored = File.read(File.join(site, ".gitignore")).lines.map(&:strip)
      assert_includes ignored, ".kamal/secrets"
      assert_includes ignored, ".env*"
      assert_includes ignored, ".contentspiel/"
      assert_includes ignored, "!.kamal/secrets.example"
    end
  end

  test "an existing folder is refused, and nothing is written" do
    in_tmp do |dir|
      site = File.join(dir, "my-site")
      FileUtils.mkdir_p(site)
      File.write(File.join(site, "keep.txt"), "mine")

      generator = ContentSpiel::SiteGenerator.new(site)
      assert_includes generator.refusal, "already exists"
      assert_raises(ContentSpiel::SiteGenerator::Refused) { generator.write }
      assert_equal [ "keep.txt" ], files_under(site)

      # An empty folder and a file are refused as well: the path must be new.
      FileUtils.mkdir_p(File.join(dir, "empty"))
      File.write(File.join(dir, "a-file"), "")
      assert ContentSpiel::SiteGenerator.new(File.join(dir, "empty")).refusal
      assert ContentSpiel::SiteGenerator.new(File.join(dir, "a-file")).refusal
      assert_empty Dir.children(File.join(dir, "empty"))
    end
  end

  test "new inside a site is refused, and nothing is written" do
    in_tmp do |dir|
      File.write(File.join(dir, ".contentspiel-version"), "0.1.0\n")

      generator = ContentSpiel::SiteGenerator.new(File.join(dir, "inner-site"))
      assert_equal "This folder is already a site; run contentspiel new outside it.", generator.refusal
      assert_raises(ContentSpiel::SiteGenerator::Refused) { generator.write }

      out, status = entrypoint("new", "inner-site", chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, "This folder is already a site; run contentspiel new outside it."
      assert_equal [ ".contentspiel-version" ], Dir.children(dir)
    end
  end

  test "a name that is not a plain folder name is refused, and nothing is written" do
    in_tmp do |dir|
      [ "My-Site", "1site", "-site", "site-", "my_site", "my site", ".hidden", "site.", "Ü" ].each do |name|
        generator = ContentSpiel::SiteGenerator.new(File.join(dir, name))
        assert generator.refusal, "#{name.inspect} must be refused"
        assert_raises(ContentSpiel::SiteGenerator::Refused) { generator.write }
      end
      assert_empty Dir.children(dir)
      assert ContentSpiel::SiteGenerator.new("#{dir}/").refusal, "a path that ends in a slash names no folder"
      [ "a/b", "../up", "", nil ].each { |name| assert ContentSpiel::SiteGenerator.name_refusal(name), name.inspect }
      assert_nil ContentSpiel::SiteGenerator.new(File.join(dir, "my-site-2")).refusal
    end
  end

  test "bin/contentspiel --version prints VERSION" do
    out, status = entrypoint("--version")
    assert status.success?
    assert_equal "#{ContentSpiel::VERSION}\n", out
  end

  test "help names every command" do
    out, status = entrypoint("help")
    assert status.success?
    %w[new generate check dev upgrade dev-files --version help].each do |command|
      assert_match(/^  #{Regexp.escape(command)}\b/, out, "help names #{command}")
    end
  end

  test "an unknown command, or none, is help and exit 2" do
    [ [ "frobnicate" ], [] ].each do |arguments|
      out, status = entrypoint(*arguments)
      assert_equal 2, status.exitstatus, arguments.inspect
      assert_includes out, "Usage: contentspiel"
    end
  end

  test "dev is not run inside the image, and upgrade outside a site's folder is refused: each says so and ends 1" do
    { "dev" => /not run inside the image/, "upgrade" => /not a site's folder/ }.each do |command, sentence|
      out, status = entrypoint(command)
      assert_equal 1, status.exitstatus, command
      assert_match(sentence, out, command)
    end
  end

  test "new refuses a bad name and an existing folder before the application starts, writing nothing" do
    in_tmp do |dir|
      FileUtils.mkdir_p(File.join(dir, "taken"))
      [ [ "new", "Bad_Name" ], [ "new", "taken" ], [ "new", "taken/inner" ], [ "new", "../up" ], [ "new" ], [ "new", "a", "b" ] ].each do |arguments|
        out, status = entrypoint(*arguments, chdir: dir)
        assert_equal 1, status.exitstatus, arguments.inspect
        assert_match(/contentspiel new/, out, arguments.inspect)
      end
      assert_equal [ "taken" ], Dir.children(dir)
      assert_empty Dir.children(File.join(dir, "taken"))
    end
  end

  # The one run that starts the application, as `new` does in the image:
  # from /rails's place, writing into the folder it was started in.
  test "new writes the site into the current folder and says what is next" do
    in_tmp do |dir|
      out, status = entrypoint("new", "demo-site", chdir: dir, env: { "RAILS_ENV" => "test" })
      assert status.success?, out
      assert_includes out, "pinned to ContentSpiel #{ContentSpiel::VERSION}"
      assert_includes out, "README.md"
      assert_equal [ "demo-site" ], Dir.children(dir)
      assert File.file?(File.join(dir, "demo-site/theme/theme.yml"))
      assert_equal "#{ContentSpiel::VERSION}\n", File.read(File.join(dir, "demo-site/.contentspiel-version"))
    end
  end

  test "new in a folder that can't be written says so in one sentence, with no stack trace, and leaves nothing" do
    in_tmp do |dir|
      File.chmod(0o555, dir)
      out, status = entrypoint("new", "demo-site", chdir: dir, env: { "RAILS_ENV" => "test" })

      assert_equal 1, status.exitstatus, out
      assert_equal "Could not write the site demo-site/ here: Permission denied. " \
                   "Check that this folder can be written, then run contentspiel new again.\n", out
      assert_empty Dir.children(dir)
    ensure
      File.chmod(0o755, dir)
    end
  end

  test "the image finds contentspiel on PATH, and its entrypoint hands it over with no db:prepare" do
    assert_match(%r{^ENV PATH="\$\{PATH\}:/rails/bin"$}, File.read(Rails.root.join("Dockerfile")))

    # The entrypoint run as the image runs it, with bin/ on PATH and no
    # database anywhere: a db:prepare would fail, and print, before the version.
    out, status = Bundler.with_unbundled_env do
      Open3.capture2e({ "PATH" => "#{ENV.fetch("PATH")}:#{Rails.root.join("bin")}", "RAILS_ENV" => nil },
                      Rails.root.join("bin/docker-entrypoint").to_s, "contentspiel", "--version", chdir: Dir.tmpdir)
    end
    assert status.success?, out
    assert_equal "#{ContentSpiel::VERSION}\n", out
  end

  private

  # The non-comment names of a secrets example.
  def example_names(secrets) = secrets.lines.grep_v(/\A\s*(#|\z)/).map { |line| line[/\A([A-Z0-9_]+)=/, 1] }

  # deploy.yml as Kamal reads it: its ERB rendered from the site's folder,
  # with the placeholders filled.
  def kamal_config(site)
    text = File.read(File.join(site, "config/deploy.yml")).gsub(/<your-[a-z-]+>/, "filled")
    Dir.chdir(site) { YAML.safe_load(ERB.new(text).result, aliases: true) }
  end

  def in_tmp(&block) = Dir.mktmpdir("site-generator", &block)

  def files_under(root)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root)
      .reject { |path| File.basename(path) == "." || File.directory?(File.join(root, path)) }
  end

  # As the image runs it: plain ruby, no bundle, the folder is the site's.
  def entrypoint(*arguments, chdir: Dir.tmpdir, env: {})
    Bundler.with_unbundled_env do
      Open3.capture2e({ "RAILS_ENV" => nil }.merge(env), "ruby", ENTRYPOINT, *arguments, chdir: chdir)
    end
  end
end
