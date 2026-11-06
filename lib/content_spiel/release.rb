require "date"
require "open3"

module ContentSpiel
  # Cutting a release (`docs/reference/hosting.md`, "Releases"): the logic of
  # `bin/rails 'release:prepare[0.5.0]'`, which is a thin wrapper, and of the
  # release workflow's notes step (`ruby -r ./lib/content_spiel/release`). Plain
  # Ruby on the standard library only, so the workflow can load it with no
  # bundle and no Rails.
  #
  # It writes two files, `lib/content_spiel/version.rb` and `CHANGELOG.md`, and
  # nothing else. It reads git (a dirty tree, a tag) and never writes to it:
  # branching, committing and pushing are the person's, so `prepare` returns the
  # commands to run instead of running them.
  class Release
    class Refused < StandardError; end

    UNRELEASED = "## Unreleased".freeze
    VERSION_LINE = /^(\s*VERSION = ")[^"]*(")/
    NUMBER = /\A\d+\.\d+\.\d+\z/

    # The text of one version's changelog section, from under its
    # `## V (date)` heading to the next `## `, without surrounding blank lines.
    def self.notes(changelog, version)
      lines = changelog.lines
      start = lines.index { |line| line.match?(/\A## #{Regexp.escape(version)}(\s|\z)/) }
      raise Refused, "CHANGELOG.md has no section for #{version}" unless start
      body = lines[(start + 1)..].take_while { |line| !line.start_with?("## ") }
      body.join.strip
    end

    def initialize(root, today: Date.today)
      @root = root.to_s
      @today = today
    end

    # Writes the new VERSION and the dated changelog section, and returns the
    # commands for the person to run. Every refusal comes before any write.
    def prepare(version)
      refuse "#{version.inspect} is not a release number (MAJOR.MINOR.PATCH)" unless version.to_s.match?(NUMBER)
      refuse "the working tree is not clean; commit or stash first" unless git("status", "--porcelain").strip.empty?
      current = current_version
      unless Gem::Version.new(version) > Gem::Version.new(current)
        refuse "#{version} is not greater than the current version #{current}"
      end
      refuse "the tag v#{version} already exists" unless git("tag", "-l", "v#{version}").strip.empty?
      changelog = File.read(changelog_path)
      refuse "#{UNRELEASED} in CHANGELOG.md is empty; there is nothing to release" if unreleased_body(changelog).strip.empty?

      File.write(version_path, File.read(version_path).sub(VERSION_LINE) { "#{$1}#{version}#{$2}" })
      File.write(changelog_path, changelog.sub(/^#{Regexp.escape(UNRELEASED)}\n/) { "#{UNRELEASED}\n\n## #{version} (#{@today.iso8601})\n" })
      commands(version)
    end

    def current_version
      File.read(version_path)[/^\s*VERSION = "([^"]*)"/, 1] or refuse("no VERSION line in lib/content_spiel/version.rb")
    end

    private

    def commands(version)
      [
        "git switch -c release-#{version}",
        "git commit -am 'chore: release #{version}'",
        "gh pr create --title 'Release #{version}' --body 'Cuts #{version}: merging this tags v#{version} and publishes the image.'"
      ]
    end

    def unreleased_body(changelog)
      lines = changelog.lines
      start = lines.index { |line| line.chomp == UNRELEASED } or refuse("CHANGELOG.md has no #{UNRELEASED} section")
      lines[(start + 1)..].take_while { |line| !line.start_with?("## ") }.join
    end

    def version_path = File.join(@root, "lib/content_spiel/version.rb")

    def changelog_path = File.join(@root, "CHANGELOG.md")

    def git(*args)
      out, err, status = Open3.capture3("git", "-C", @root, *args)
      refuse "git #{args.first} failed: #{err.strip}" unless status.success?
      out
    end

    def refuse(message) = raise(Refused, message)
  end
end
