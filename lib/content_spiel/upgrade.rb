require "pathname"
require_relative "version"
require_relative "release"
require_relative "dev_files"

module ContentSpiel
  # `contentspiel upgrade` (bin/contentspiel), run by the NEWEST image: the
  # wrapper pulls and runs `stable` for this command, whatever the site pins
  # (releases spec, "Upgrading").
  #
  #   ContentSpiel::Upgrade.new("/site", changelog: File.read("CHANGELOG.md"), check: -> { problems }).run
  #   # => Result(code: 0, text: "…")
  #
  # WHAT IT DOES, in this order, and stops at the first that says no:
  # 1. reads the pin, `.contentspiel-version`, which must be a release number
  #    (`stable` is a way of running a command, not a version a site can be
  #    on) and not newer than this image (a downgrade is refused; so is a
  #    `stable` that is behind the pin);
  # 2. says so, and writes nothing, when the pin IS this version;
  # 3. prints every changelog section newer than the pin, up to this
  #    version, oldest first (`Release.sections_between`);
  # 4. runs the theme check on the site's theme/ (`check`, handed in: the
  #    application starts only when it is called, so 1 and 2 answer at once);
  # 5. only when the check has no problem, moves the pin and prints the next
  #    steps. The pin is the last thing written, so a theme that fails
  #    leaves the site exactly as it was.
  #
  # THE OUTPUT IS FOR AN AI TOOL AS MUCH AS FOR A PERSON: plain sentences, the
  # same three headings every time ("Release notes", "Theme check", "Next
  # steps"), no colour and no cursor movement, whether or not stdout is a
  # terminal. A refusal is `Refused` (the entrypoint prints it to stderr, exit
  # 1); a theme that fails the check is a Result with code 1, whose text
  # carries the notes and the check's problems, since those are what is
  # asked for next.
  #
  # Plain Ruby on the standard library, like Release and DevFiles.
  class Upgrade
    class Refused < StandardError; end

    Result = Struct.new(:code, :text)

    # The subsections shown first in each section, in this order: what a
    # person must act on before anything else. The rest follow in file order.
    # Release's list, which the GitHub Release's notes are ordered by too.
    FIRST = Release::FIRST
    # A section with either heading changed the database, so going back
    # past it is not safe: "Migrations" lists every migration, "Migrations
    # needing action" those a person must do something about.
    MIGRATIONS = [ "Migrations", "Migrations needing action" ].freeze
    PIN = ".contentspiel-version".freeze
    # The backup command of the site's README (lib/site_template/README.md.tt).
    BACKUP = 'kamal accessory exec db --reuse --raw "pg_dumpall -U postgres" > backup.sql'.freeze

    def initialize(site, changelog:, check:, version: ContentSpiel::VERSION)
      @site = Pathname(File.expand_path(site.to_s))
      @changelog = changelog
      @check = check
      @version = version
    end

    def run
      pinned = read_pin
      return Result.new(0, "This site is already on ContentSpiel #{@version}. Nothing to do.") if pinned == @version

      sections = Release.sections_between(@changelog, pinned, @version)
      notes = notes_text(pinned, sections)
      problems = @check.call
      return failed(notes, problems) if problems.any?

      write_pin
      Result.new(0, [ notes, "Theme check\n\n#{theme_line}: no problems.", next_steps(pinned, sections) ].join("\n\n"))
    end

    private

    def read_pin
      file = @site.join(PIN)
      raise Refused, "This is not a site's folder: there is no #{PIN} here." unless file.file?
      raise Refused, "There is no theme/ here: run contentspiel upgrade in the site's folder." unless @site.join("theme").directory?

      pinned = file.read.lines.first.to_s.strip
      unless pinned.match?(Release::NUMBER)
        raise Refused, "#{PIN} must hold a release number, X.Y.Z, and holds #{pinned.inspect}. " \
                       "A site pins a number, not `stable`: write the version it runs now, then run contentspiel upgrade again."
      end
      if Gem::Version.new(pinned) > Gem::Version.new(@version)
        raise Refused, "This site is pinned to #{pinned}, which is newer than the #{@version} this command ran from. " \
                       "Nothing was changed. A site is never moved back; pull the newest image and run contentspiel upgrade again."
      end
      pinned
    end

    def notes_text(pinned, sections)
      head = "Release notes\n\nChanges from ContentSpiel #{pinned} to #{@version}, oldest release first."
      parts = sections.map { |version, body| "## #{version}\n\n#{Release.order(body)}".rstrip }
      # This image's own version should have a section; if it has none, say
      # so among the notes rather than let the gap pass unseen.
      parts << "CHANGELOG has no section for #{@version}." unless sections.any? { |version, _| version == @version }
      ([ head ] + parts).join("\n\n")
    end

    def failed(notes, problems)
      lines = problems.each_with_index.map { |problem, index| "#{(index + 1).to_s.rjust(problems.size.to_s.size)}. #{problem}" }
      count = "#{problems.size} #{problems.size == 1 ? "problem" : "problems"}"
      text = [ notes,
               "Theme check\n\n#{lines.join("\n")}\n#{theme_line}: #{count}.",
               "The version was not moved: #{PIN} still holds the old version. Fix theme/ against the release notes " \
               "above, then run contentspiel upgrade again." ].join("\n\n")
      Result.new(1, text)
    end

    def theme_line = @site.join("theme").to_s

    def next_steps(pinned, sections)
      steps = [ "Next steps", "contentspiel upgrade moved this site from #{pinned} to #{@version}; #{PIN} now holds #{@version}.",
                "1. Review the release notes above.",
                "2. Commit #{PIN} (and any change to theme/).",
                "3. Deploy: kamal deploy" ]
      if sections.any? { |_, body| MIGRATIONS.any? { |heading| body.match?(/^### #{Regexp.escape(heading)}[ \t]*$/) } }
        steps << "A release between them changes the database. Going back to #{pinned} after deploying is not safe: " \
                 "make a backup before step 3 (the README's command: #{BACKUP})."
      end
      volume = DevFiles.new(@site).builds_volume(pinned)
      steps << "If you run the site on this machine with contentspiel dev, remove the old stylesheet volume: docker volume rm #{volume}"
      steps.join("\n")
    end

    # Temp file in the site's folder and a rename: the pin is whole or it is
    # the old one, never half-written. The image runs as the person, so the
    # file is theirs.
    def write_pin
      temp = @site.join("#{PIN}.tmp#{Process.pid}")
      temp.write("#{@version}\n")
      temp.chmod(@site.join(PIN).stat.mode & 0o7777)
      File.rename(temp, @site.join(PIN))
    ensure
      File.delete(temp) if temp&.exist? # version: none (a temp file in the site's folder, no database row)
    end
  end
end
