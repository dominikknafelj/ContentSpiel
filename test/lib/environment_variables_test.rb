require "test_helper"

# Every environment variable the application's code reads is listed in
# docs/reference/hosting.md, "Every variable the code reads", with who sets
# it, its default and whether it is a secret, so a host reads one table and
# not the code. This reads the code under app, config and lib for the names
# and fails on one the table does not list, and on a row whose name nothing
# reads any more.
#
# A name is found in two ways:
# - written at the read: `ENV["NAME"]`, `ENV.fetch("NAME"…)` or
#   `ENV.fetch "NAME"`, `ENV.key?`, `include?`, `has_key?`, `member?`, every
#   name of `ENV.values_at(…)` and `ENV.slice(…)`, and `env["NAME"]` on an
#   `env` handed in for tests (`HostSettings`, `Telemetry`), in Ruby, a rake
#   task, and the ERB of a YAML file or a site template;
# - held in a constant and read through it (`ENV[name]`, `@env[ENV_NAMES…]`,
#   a name built by interpolation): every such read is named in INDIRECT, by
#   its file and its line, with the names it reads, so a new indirect read
#   fails even in a file that already has one, as does an entry whose line is
#   gone.
# Any other method called on `ENV` (`ENV.to_h`, `ENV.each`) fails too: it
# reads names this test cannot see, so it is rewritten into one of the forms
# above. A Rack env (`request.env["HTTP_…"]`, `req.env[…]`) is not the
# process's environment and is never read as one.
#
# LEFT OUT ON PURPOSE: `db/` (a migration that reads a variable, as
# `DropActionText` reads `FORCE_DROP_ACTION_TEXT`, is a switch for the person
# running that one migration, never something a host sets; the seeds read
# none). WHAT THIS CANNOT SEE: a variable read by a gem or by Rails itself
# (`RAILS_MASTER_KEY`, `DATABASE_URL`, libpq's `PG*`, Puma's and Thruster's
# own), which the reference lists apart, by hand; `bin/` and the Dockerfile,
# which are the image's and the wrapper's; and a read through an object that
# is called neither `ENV` nor `env`.
class EnvironmentVariablesTest < ActiveSupport::TestCase
  ROOTS = %w[app config lib].freeze
  SOURCES = "**/*.{rb,rake,yml,erb,tt}".freeze
  DOC = Rails.root.join("docs/reference/hosting.md")
  HEADING = "## Every variable the code reads".freeze

  ONE_NAME = %w[fetch key? include? has_key? member?].freeze
  MANY_NAMES = %w[values_at slice].freeze
  # `ENV` itself, or an `env`/`@env` that is not a method's receiver's
  # (`request.env`, `req.env` are Rack's).
  RECEIVER = /(?:\bENV|(?<![.\w@])@?env)/
  READER = /#{RECEIVER}(?:\[|\.(?:#{ONE_NAME.map { |name| Regexp.escape(name) }.join("|")})(?:\(|\s+))\s*/
  WRITTEN = /#{READER}["']([A-Z][A-Z0-9_]*)["']/
  LISTS = /#{RECEIVER}\.(?:#{MANY_NAMES.join("|")})(?:\(|\s+)([^)\n]*)/
  # A read whose name is not a plain literal: a constant, a variable, or an
  # interpolated string.
  INDIRECT_READ = /#{READER}(?:[A-Za-z_@:]|["'][A-Z0-9_]*#\{)/
  ENV_CALL = /\bENV\.(\w+[?!]?)/

  ENCRYPTION_KEYS = lambda do
    source = Rails.root.join("config/application.rb").read
    keys = source[/%w\[([^\]]*)\]\.each do \|name\|\n\s*value = ENV\["ACTIVE_RECORD_ENCRYPTION_/, 1] or raise "config/application.rb no longer reads the encryption keys from a %w[] list: update ENCRYPTION_KEYS"
    keys.split.map { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}" }
  end

  # [file, the line as written, without a trailing comment] => the names it reads.
  INDIRECT = {
    [ "config/application.rb", 'value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]' ] => ENCRYPTION_KEYS,
    [ "lib/site_address.rb", "source = VARIABLES.find { |name| !ENV[name].to_s.strip.empty? }" ] => -> { SiteAddress::VARIABLES },
    [ "lib/site_address.rb", "parse(source && ENV[source], source: source || VARIABLES.first)" ] => -> { SiteAddress::VARIABLES },
    [ "lib/theme_folder.rb", "value = env[VARIABLE].to_s.strip" ] => -> { [ ThemeFolder::VARIABLE ] },
    [ "lib/tasks/theme.rake", "named = ENV[ThemeFolder::VARIABLE].to_s.strip" ] => -> { [ ThemeFolder::VARIABLE ] },
    [ "lib/tasks/theme.rake", "ENV[ThemeFolder::VARIABLE] = nil" ] => -> { [ ThemeFolder::VARIABLE ] },
    [ "lib/telemetry.rb", "return :otlp if ENDPOINTS.any? { |name| !env[name].to_s.strip.empty? }" ] => -> { Telemetry::ENDPOINTS },
    [ "lib/telemetry.rb", 'return :console if env[CONSOLE] == "1"' ] => -> { [ Telemetry::CONSOLE ] },
    [ "app/values/mail_settings.rb", "@env[ENV_NAMES.fetch(field)].to_s.strip.presence" ] => -> { MailSettings::ENV_NAMES.values }
  }.freeze

  def self.code_lines(path)
    File.readlines(path).each_with_index.reject { |line, _| line.lstrip.start_with?("#", "<%#") }
  end

  def self.written(line) = line.scan(WRITTEN).flatten + line.scan(LISTS).flat_map { |(args)| args.scan(/["']([A-Z][A-Z0-9_]*)["']/).flatten }

  def self.without_comment(line) = line.strip.sub(/\s+#\s.*\z/, "")

  def sources
    @sources ||= ROOTS.flat_map { |root| Dir[Rails.root.join(root, SOURCES)] }.sort.to_h do |path|
      [ Pathname(path).relative_path_from(Rails.root).to_s, self.class.code_lines(path) ]
    end
  end

  def code = sources.flat_map { |path, lines| lines.map { |line, number| [ path, number + 1, line ] } }

  def written_names = code.flat_map { |_, _, line| self.class.written(line) }.uniq

  def indirect_reads = code.select { |_, _, line| line.match?(INDIRECT_READ) }

  def read_names = (written_names + INDIRECT.values.flat_map(&:call)).uniq.sort

  def listed_names
    text = DOC.read
    start = text.index("\n#{HEADING}\n") or flunk("#{DOC} has no section #{HEADING.inspect}")
    section = text[start + 1..].then { |rest| rest[0...(rest.index("\n## ", 1) || rest.length)] }
    section.scan(/^\| `([A-Z][A-Z0-9_]*)` \|/).flatten
  end

  test "every variable the code reads is listed in the hosting reference, and every listed one is read" do
    listed = listed_names
    assert_equal listed.uniq, listed, "a variable is listed twice in #{HEADING}"

    unlisted = read_names - listed
    assert_empty unlisted, "the code reads these, and docs/reference/hosting.md, #{HEADING.inspect}, does not list them: add a row with who sets it, its default and whether it is a secret"
    stale = listed - read_names
    assert_empty stale, "#{HEADING.inspect} lists these, and nothing under #{ROOTS.join(", ")} reads them: delete the row, or move it to the list of what Rails, a gem or the image reads"
  end

  test "every read through a name held elsewhere is accounted for by its line, and every account still matches a read" do
    found = indirect_reads.map { |path, _, line| [ path, self.class.without_comment(line) ] }
    unaccounted = indirect_reads.reject { |path, _, line| INDIRECT.key?([ path, self.class.without_comment(line) ]) }
    assert_empty unaccounted.map { |path, number, line| "#{path}:#{number}: #{line.strip}" },
      "a variable is read through a name that is not written at the read: add the line to INDIRECT with the names it reads"

    stale = INDIRECT.keys - found
    assert_empty stale.map { |path, line| "#{path}: #{line}" }, "INDIRECT names a line that is no longer in its file: change or delete its entry"
  end

  test "ENV is read only in the forms this test sees" do
    known = ONE_NAME + MANY_NAMES
    unknown = code.flat_map { |path, number, line| line.scan(ENV_CALL).flatten.reject { |name| known.include?(name) }.map { |name| "#{path}:#{number}: ENV.#{name}" } }
    assert_empty unknown, "ENV is read through a method this test cannot follow: read a variable by its name (ENV[\"NAME\"], ENV.fetch(\"NAME\", …))"
  end

  test "the patterns find a written name in every form, an indirect read, and nothing in a Rack env" do
    assert_equal [ "PORT" ], self.class.written('port ENV.fetch("PORT", 3000)')
    assert_equal [ "PORT" ], self.class.written('port ENV.fetch "PORT", 3000')
    assert_equal [ "A" ], self.class.written('ENV.include?("A")')
    assert_equal [ "A" ], self.class.written('ENV.has_key? "A"')
    assert_equal %w[A B], self.class.written('ENV.values_at("A", "B")')
    assert_equal %w[A B], self.class.written('ENV.slice("A", "B")')
    assert_equal [ "ASSUME_SSL" ], self.class.written('env["ASSUME_SSL"] == "1"')
    assert_match INDIRECT_READ, 'value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]'
    assert_match INDIRECT_READ, "@env[ENV_NAMES.fetch(field)]"
    assert_match INDIRECT_READ, "ENV.fetch name"
    assert_empty self.class.written('request.env["HTTP_X_FORWARDED_PROTO"]')
    assert_empty self.class.written('req.env["rack.attack.match_data"]')
    assert_no_match INDIRECT_READ, "request.env[key]"
    assert_equal [ "to_h" ], 'ENV.to_h["A"]'.scan(ENV_CALL).flatten
  end
end
