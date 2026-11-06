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
    # The one way the heading is found, for the empty check and for the
    # rewrite alike; LF or CRLF, or the end of the file.
    UNRELEASED_HEADING = /^## Unreleased[ \t]*(\r?\n|\z)/
    VERSION_LINE = /^(\s*VERSION = ")[^"]*(")/
    NUMBER = /\A\d+\.\d+\.\d+\z/

    # The subsections a reader must act on, first in a section and in this
    # order: what breaks, what a theme must change, what is gone, what a
    # person must do to the database, what the host must set. The rest follow
    # in file order. One list for both readers of a section: the GitHub
    # Release's notes (release.yml, `notes(…, ordered: true)`) and
    # `contentspiel upgrade` (`ContentSpiel::Upgrade`).
    FIRST = [ "Breaking", "Theme contract", "Removed", "Migrations needing action", "Environment" ].freeze

    # The text of one version's changelog section, from under its
    # `## V (date)` heading to the next `## `, without surrounding blank
    # lines; with `ordered: true`, its subsections in FIRST's order (`order`).
    # Refused when there is no such section, and when the section holds
    # nothing but whitespace: a release's notes are never empty.
    def self.notes(changelog, version, ordered: false)
      body = section(changelog, version)
      raise Refused, "CHANGELOG.md has no section for #{version}" unless body
      raise Refused, "CHANGELOG.md's section for #{version} is empty" if body.empty?

      ordered ? order(body) : body
    end

    # A section's body with the subsections of FIRST moved to the top, in
    # FIRST's order, each with its heading, and the rest after them in file
    # order. Lines before the first heading stay at the very top.
    def self.order(body)
      parts = body.split(/^(?=### )/)
      preamble = parts.first&.start_with?("### ") ? "" : parts.shift
      title = ->(part) { part[/\A### (.*)$/, 1].to_s.strip }
      first = FIRST.flat_map { |name| parts.select { |part| title.(part) == name } }
      ([ preamble.to_s ] + first + (parts - first)).map(&:strip).reject(&:empty?).join("\n\n")
    end

    # Every released section with `from` < version <= `to`, oldest first, as
    # [[version, body]]. `## Unreleased` is never one (it is no number), and
    # a heading that is no X.Y.Z is skipped. `contentspiel upgrade` shows
    # these; the body of each is found as `notes` finds it, so there is one
    # parser, but an empty one is passed over and not refused: a site's
    # upgrade does not stop on a release that said nothing.
    def self.sections_between(changelog, from, to)
      low = Gem::Version.new(from)
      high = Gem::Version.new(to)
      versions = changelog.scan(/^## (\d+\.\d+\.\d+)(?=\s|\z)/).flatten.uniq
      versions.select { |v| Gem::Version.new(v) > low && Gem::Version.new(v) <= high }
              .sort_by { |v| Gem::Version.new(v) }
              .map { |v| [ v, section(changelog, v) ] }
    end

    # The body under `## V`, stripped, or nil when there is no such heading.
    def self.section(changelog, version)
      lines = changelog.lines
      start = lines.index { |line| line.match?(/\A## #{Regexp.escape(version)}(\s|\z)/) }
      return nil unless start

      lines[(start + 1)..].take_while { |line| !line.start_with?("## ") }.join.strip
    end
    private_class_method :section

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
      body = unreleased_body(changelog)
      # Only sub-headings (### Added) and blank lines: nothing to release.
      if body.lines.all? { |line| line.strip.empty? || line.start_with?("### ") }
        refuse "#{UNRELEASED} in CHANGELOG.md is empty; there is nothing to release"
      end

      versioned = File.read(version_path).sub(VERSION_LINE) { "#{$1}#{version}#{$2}" }
      dated = changelog.sub(UNRELEASED_HEADING) { "#{UNRELEASED}#{$1}#{$1}## #{version} (#{@today.iso8601})#{$1}" }
      refuse "could not rewrite #{UNRELEASED} in CHANGELOG.md" if dated == changelog
      File.write(version_path, versioned)
      File.write(changelog_path, dated)
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
        "git push -u origin release-#{version}",
        "gh pr create --title 'Release #{version}' --body 'Cuts #{version}: merging this tags v#{version} and publishes the image.'"
      ]
    end

    def unreleased_body(changelog)
      match = changelog.match(UNRELEASED_HEADING) or refuse("CHANGELOG.md has no #{UNRELEASED} section")
      match.post_match.lines.take_while { |line| !line.start_with?("## ") }.join
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
