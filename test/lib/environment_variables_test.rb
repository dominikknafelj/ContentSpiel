require "test_helper"

# Every environment variable the application's code reads is listed in
# docs/reference/hosting.md, "Every variable", with who sets it, its default
# and whether it is a secret, so a host reads one table and not the code
# (issue #138). This reads the code under app, config and lib for the names
# and fails on one the table does not list, and on a row whose name nothing
# reads any more.
#
# A name is found in two ways:
# - written at the read: `ENV["NAME"]`, `ENV.fetch("NAME"…)`, and the same on
#   an `env` handed in for tests (`env["ASSUME_SSL"]`), in Ruby, a rake task,
#   and the ERB of a YAML file or a site template;
# - held in a constant and read through it (`ENV[name]`, `@env[ENV_NAMES…]`,
#   a name built by interpolation): every such read is named in INDIRECT
#   with the names it reads, and a read through a name that is neither
#   written nor listed there fails, as does an INDIRECT entry whose file
#   reads nothing that way any more.
#
# WHAT THIS CANNOT SEE: a variable read by a gem or by Rails itself
# (`RAILS_MASTER_KEY`, `DATABASE_URL`, libpq's `PG*`, Puma's and Thruster's
# own), which the reference lists apart, by hand; `bin/` and the Dockerfile,
# which are the image's and the wrapper's; and a read through an object that
# is not called `ENV` or `env`.
class EnvironmentVariablesTest < ActiveSupport::TestCase
  ROOTS = %w[app config lib].freeze
  SOURCES = "**/*.{rb,rake,yml,erb,tt}".freeze
  DOC = Rails.root.join("docs/reference/hosting.md")
  HEADING = "## Every variable the code reads".freeze

  READER = /\b(?:ENV|env)\s*(?:\[|\.fetch\(|\.key\?\()\s*/
  WRITTEN = /#{READER}["']([A-Z][A-Z0-9_]*)["']/
  # A read whose name is not a plain literal: a constant, a variable, or an
  # interpolated string.
  INDIRECT_READ = /#{READER}(?:[A-Za-z_@:]|["'][A-Z0-9_]*#\{)/

  INDIRECT = {
    "config/application.rb" => -> { %w[PRIMARY_KEY DETERMINISTIC_KEY KEY_DERIVATION_SALT].map { |key| "ACTIVE_RECORD_ENCRYPTION_#{key}" } },
    "lib/site_address.rb" => -> { SiteAddress::VARIABLES },
    "lib/theme_folder.rb" => -> { [ ThemeFolder::VARIABLE ] },
    "lib/tasks/theme.rake" => -> { [ ThemeFolder::VARIABLE ] },
    "lib/telemetry.rb" => -> { Telemetry::ENDPOINTS + [ Telemetry::CONSOLE ] },
    "app/values/mail_settings.rb" => -> { MailSettings::ENV_NAMES.values }
  }.freeze

  def self.code_lines(path)
    File.readlines(path).each_with_index.reject { |line, _| line.lstrip.start_with?("#", "<%#") }
  end

  def sources
    ROOTS.flat_map { |root| Dir[Rails.root.join(root, SOURCES)] }.sort.to_h do |path|
      [ Pathname(path).relative_path_from(Rails.root).to_s, self.class.code_lines(path) ]
    end
  end

  def written_names = sources.values.flatten(1).flat_map { |line, _| line.scan(WRITTEN).flatten }.uniq

  def indirect_reads
    sources.flat_map do |path, lines|
      lines.select { |line, _| line.match?(INDIRECT_READ) }.map { |line, number| [ path, number + 1, line.strip ] }
    end
  end

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

  test "every read through a name held elsewhere is accounted for, and every account still matches a read" do
    reads = indirect_reads
    unaccounted = reads.reject { |path, _, _| INDIRECT.key?(path) }
    assert_empty unaccounted.map { |path, number, line| "#{path}:#{number}: #{line}" },
      "a variable is read through a name that is not written at the read: add the file to INDIRECT with the names it reads"

    stale = INDIRECT.keys - reads.map(&:first)
    assert_empty stale, "INDIRECT names a file that reads no variable through a held name any more: delete its entry"
  end

  test "the patterns find a written name, an indirect read, and nothing in a comment or a Rack env" do
    assert_equal [ "PORT" ], 'port ENV.fetch("PORT", 3000)'.scan(WRITTEN).flatten
    assert_equal [ "ASSUME_SSL" ], 'env["ASSUME_SSL"] == "1"'.scan(WRITTEN).flatten
    assert_match INDIRECT_READ, 'value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]'
    assert_match INDIRECT_READ, "@env[ENV_NAMES.fetch(field)]"
    assert_no_match INDIRECT_READ, 'req.env["rack.attack.match_data"]'
    assert_empty 'req.env["rack.attack.match_data"]'.scan(WRITTEN)
  end
end
