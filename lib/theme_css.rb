require "pathname"
require "fileutils"
require "securerandom"

# The public stylesheet's build (theming spec §4). ONE stylesheet, built from
# an entry file this module writes:
#
#   @import "<default theme>/theme.css";              tokens, base, prose, sections, the default templates' utilities
#   @import "<a type's stylesheet>";                  each registered block type's, in registration order (block types spec, decision 7)
#   @import "<theme>/assets/stylesheets/theme.css";   the theme's own styles
#   @source "<default theme>";                        for the watch alone, see below
#   @source "<theme>/assets/stylesheets";             for the watch alone
#   @source "<theme>/views";                          so utilities in the theme's templates are built
#   @source "<theme>/components";
#
# Without a theme only the first and the third line are there, which is the
# build the CMS always had. What follows from the order:
# - a theme changes a token by declaring it again, and copies nothing;
# - a template the theme does not replace is still styled, because the
#   default theme's styles are always in the build. That is what makes the
#   fallback real, and why the preview bar keeps its look under any theme;
# - a theme may write plain CSS or Tailwind utilities, through the same
#   executable.
# The default theme's own stylesheets (tokens, base, prose, sections) come
# first by this fixed rule whatever the registration order (the owner's answer
# 4), then each registered type's stylesheet once, then the theme's, so a
# theme still re-colours a block by declaring its token again.
# `theme_css:watch` reads the types once when it starts, so a new type's
# stylesheet needs the watch restarted.
# All the imports come before the `@source` lines: an `@import` after another
# rule is not an import.
#
# THE TWO `@source` LINES THAT NAME A FOLDER OF STYLESHEETS add nothing to
# the build (Tailwind reads no class name out of a .css file: the output
# with them is byte for byte the output without, measured for both themes)
# and are there for `theme_css:watch`. Tailwind's watcher watches the
# folder the entry file is in and the folders its `@source` lines name, and
# nothing else: not the folder of a file the entry imports. While the entry
# WAS the default theme's theme.css, that folder was watched for being the
# entry's own; now the entry is in tmp/theme, and without these lines a
# change to tokens.css, prose.css or a theme's theme.css was built by
# nobody until the watch was started again (seen: the stylesheet stayed as
# it was, with no word in the log).
#
# Paths are written relative to the entry file, so the entry reads the same
# on a laptop and in an image. The theme's are relative from where the
# folder REALLY is (`realpath`): the watcher reports a changed file by its
# real path and compares it with the path it was told, so a theme reached
# through a link (on macOS every temporary folder is: /var is a link to
# /private/var) was built once and a changed template of it never again.
#
# WHEN: at image build, never at boot. `assets:precompile` runs
# `tailwindcss:build`, which runs `theme_css:build` (lib/tasks/theme_css.rake),
# with THEME_PATH set by the site's Dockerfile. The build stamps its output
# with the theme's fingerprint (`ThemeFolder::STAMP`), and production does
# not start when the stamp is another theme's (config/application.rb). In
# development `theme_css:watch` (Procfile.dev) builds the same entry as the
# theme is written and keeps the stamp its own (`keep_stamped`); nothing
# refuses there, and System status says when the stamp is another's.
#
# DEVELOPMENT AND TEST SHARE THE OUTPUT AND THE ENTRY. `bin/rails test`
# builds the default theme's stylesheet (the test environment ignores
# THEME_PATH) into the same app/assets/builds, from the same
# tmp/theme/entry.css, also while a watch runs for a theme: the site in
# development is then drawn with the default stylesheet until
# `bin/rails tailwindcss:build` is run with THEME_PATH set, or the watch is
# started again. System status says so, and so does the test build itself
# (lib/tasks/theme_css.rake). An output per environment is not built.
module ThemeCss
  DEFAULT = "app/assets/tailwind/themes/default/theme.css".freeze
  ENTRY = "tmp/theme/entry.css".freeze
  OUTPUT = "app/assets/builds/theme.css".freeze

  # A registered block type's part of the build (block types spec, decision
  # 7): its stylesheet, imported after the default theme's own and before the
  # theme's, and the folder of its component when that is not
  # app/components/blocks (which the default theme's own `@source` line
  # scans), so utilities in an engine's template are built. Handed in by the
  # caller (lib/tasks/theme_css.rake, from `BlockTypes.theme_css_blocks`):
  # this file loads before the application and reads no registry. `type` is
  # the type's name, for a message about its stylesheet.
  #
  # Both paths are written into the entry by where they REALLY are
  # (`realpath`), as the theme's are, for the reason the header gives: a gem
  # is often reached through a link (a bundle path under a linked folder).
  Block = Data.define(:stylesheet, :source, :type) do
    def initialize(stylesheet:, source:, type: nil) = super
  end

  # A registered type's stylesheet that is not there when the entry is
  # written: a gem's file deleted or moved since it was registered (its
  # registration reads it once, `BlockTypeDefinition#refuse_outside!`).
  class MissingStylesheet < StandardError; end

  module_function

  def entry(folder, root:, blocks: [])
    from = Pathname(root).join(ENTRY).dirname
    relative = ->(path) { Pathname(path).relative_path_from(from).to_s }
    default = Pathname(root).join(DEFAULT)

    imports = [ default ]
    sources = [ default.dirname ]
    blocks.each do |block|
      next unless block.stylesheet

      sheet = real_stylesheet(block)
      imports << sheet
      sources << sheet.dirname
    end
    sources.concat(blocks.filter_map { |block| block.source && real(block.source) })
    if folder.configured?
      theme = folder.path.realpath
      if (stylesheet = folder.stylesheet&.relative_path_from(folder.path))
        imports << theme.join(stylesheet)
        sources << theme.join(stylesheet).dirname
      end
      # The scripts as well as the templates: a utility that only a
      # controller writes (`classList.add("hidden")`) is a class like any
      # other, and one no template happens to use would not be built.
      sources.concat(%w[views components javascript].map { |name| theme.join(name) }.select(&:directory?))
    end

    lines = imports.uniq.map { |path| %(@import "#{relative.(path)}";) } + sources.uniq.map { |path| %(@source "#{relative.(path)}";) }
    lines.join("\n") + "\n"
  end

  # A type's stylesheet by its real path; one that is not there is that
  # type's, by name (`MissingStylesheet`).
  def real_stylesheet(block)
    Pathname(block.stylesheet).realpath
  rescue SystemCallError => error
    whose = block.type ? " of the block type #{block.type}" : ""
    raise MissingStylesheet, "the stylesheet#{whose} cannot be read (#{error.class}): #{block.stylesheet}"
  end

  # A folder by its real path, or as it was given when it cannot be
  # resolved: a component's folder exists while its class is loaded.
  def real(path)
    Pathname(path).realpath
  rescue SystemCallError
    Pathname(path)
  end

  def write_entry(folder, root:, blocks: [])
    path = Pathname(root).join(ENTRY)
    FileUtils.mkdir_p(path.dirname)
    path.write(entry(folder, root: root, blocks: blocks))
    path
  end

  def command(root:, executable:)
    [ executable, "-i", File.join(root.to_s, ENTRY), "-o", File.join(root.to_s, OUTPUT), "--minify" ]
  end

  # `fingerprint` is handed in by a caller that has read it already and
  # must have THAT value written (`build`, `keep_stamped`): the folder can
  # change between two readings.
  #
  # PUT IN PLACE WHOLE: written beside, then renamed. A plain write empties
  # the file before it fills it, and a reader in between (the keeper below
  # asks every second, System status on every view) read an EMPTY stamp,
  # which is neither "no build" nor anybody's fingerprint. Ruby hands the
  # interpreter's lock to a waiting thread at exactly that `open`, so
  # within one process it was no rare moment. The file beside is a dot
  # file too (app/assets/builds is on the asset load path, where anything
  # else is an asset), and its name ends in random characters: the process's
  # id and the thread's would be ONE name in two containers that share the
  # folder (a container's first process is pid 1, and the main thread has
  # the same id in every fresh Ruby), and one would rename the other's
  # half-written file into place. Whatever happens, it is not left behind:
  # after the rename it is gone, and after a failure it is deleted.
  def stamp!(folder, root:, fingerprint: folder.fingerprint)
    path = Pathname(root).join(ThemeFolder::STAMP)
    FileUtils.mkdir_p(path.dirname)
    beside = Pathname("#{path}.#{SecureRandom.hex(8)}")
    beside.write("#{fingerprint}\n")
    File.rename(beside, path)
  ensure
    FileUtils.rm_f(beside) if beside
  end

  def unstamp!(root:)
    FileUtils.rm_f(Pathname(root).join(ThemeFolder::STAMP))
  end

  # The build both tasks run (lib/tasks/theme_css.rake). THE STAMP VOUCHES
  # FOR A BUILD THAT SUCCEEDED, AND FOR NOTHING ELSE: it is taken away
  # before the executable starts and written after it ended well, so a build
  # that fails (a CSS error, a killed process) leaves no stamp, an earlier
  # build's included. And it is the fingerprint read BEFORE the build: a
  # file of the theme changed while the executable ran may or may not be in
  # the output, so the folder then no longer matches its stamp.
  def build(folder, root:, executable:, blocks: [])
    fingerprint = folder.fingerprint
    unstamp!(root: root)
    write_entry(folder, root: root, blocks: blocks)
    system(*command(root: root, executable: executable), exception: true)
    stamp!(folder, root: root, fingerprint: fingerprint)
  end

  # For the watch (lib/tasks/theme_css.rake): a thread that keeps the stamp
  # true while a theme is written. Tailwind's watcher rebuilds the
  # stylesheet on a change by itself, but nobody hears whether that build
  # succeeded, and the folder's fingerprint changes with every edit. So when
  # the folder has changed, the keeper builds once itself (`build`, a
  # callable that answers whether it succeeded) and stamps what it built; a
  # build that fails takes the stamp away. System status then warns in
  # development only about a stylesheet that is not this folder's.
  #
  # Every `every` seconds it GLANCES at the folder (names, sizes, times:
  # `ThemeFolder#glance`) and reads the stamp, and hashes the folder only
  # when one of the two changed: a theme with large images costs a listing
  # a second, not a read of every file.
  #
  # It follows the folder and nothing else. It builds only while the stamp
  # is still its own (the last it wrote, or none after its own failed
  # build). A stamp somebody else wrote since (`bin/rails test` builds the
  # default theme's stylesheet into the same app/assets/builds, entry file
  # and all) is left as it is, because the stylesheet is then theirs too,
  # and System status goes on saying so. When the stamp is the folder's
  # fingerprint again (`bin/rails tailwindcss:build` with THEME_PATH set),
  # the keeper takes it for its own and goes on.
  #
  # The fingerprint is read ONCE a turn and that value is the one written
  # and remembered: a keeper that stamped a second reading while it
  # remembered the first took its own stamp for somebody else's after the
  # next change, and never wrote again.
  #
  # The STAMP is read once a turn too, and what the turn remembers as seen
  # is that reading, or what it wrote itself: never a second reading. A
  # stamp another build wrote while the turn hashed the folder was otherwise
  # remembered as seen without having been judged, no later turn looked at
  # it again, the keeper never took it for its own, and from then on it
  # built and stamped nothing (the first CI run of the branch). Remembered
  # as it was judged, the newer stamp differs at the next turn and is
  # judged there.
  #
  # The entry file is written again before a build when it is no longer the
  # folder's (a theme that gained its stylesheet or its components folder
  # since the watch started); Tailwind's watcher watches tmp/theme and
  # follows.
  #
  # nil without a theme folder: the default theme's fingerprint never
  # changes. An error of any kind in a turn (a file half written, a link
  # not yet made, anything else) is said once, by its class and without a
  # path, and the turn is tried again: a thread that died would leave the
  # watch running with a stamp nobody keeps.
  #
  # The thread counts the turns it has ENDED (`thread_variable_get(:turns)`:
  # one that found nothing changed, one that built, one that raised). The
  # watch does not read it. It is there for whoever must know that the
  # keeper has looked since something happened, which is the tests: they
  # waited a third of a second for that instead, and a keeper that had not
  # had its turn by then failed them as the defect above did.
  def keep_stamped(folder, root:, build:, blocks: [], every: 1, log: ->(line) { warn line })
    return nil unless folder.configured?

    mine = ThemeFolder.stamp(root)
    seen = [ folder.glance, mine ]
    said = false

    Thread.new do
      Thread.current.thread_variable_set(:turns, 0)
      loop do
        sleep every
        begin
          stamp = ThemeFolder.stamp(root)
          look = folder.glance
          next if seen == [ look, stamp ]

          fingerprint = folder.fingerprint
          if stamp == fingerprint
            mine = stamp
          elsif stamp == mine
            write_entry(folder, root: root, blocks: blocks) unless current_entry?(folder, root: root, blocks: blocks)
            if build.call
              stamp!(folder, root: root, fingerprint: fingerprint)
              mine = fingerprint
            else
              unstamp!(root: root)
              mine = nil
            end
            stamp = mine
          end
          seen = [ look, stamp ]
        rescue StandardError => error
          log.call("theme_css:watch: the stylesheet's stamp could not be kept (#{error.class}); it will be tried again") unless said
          said = true
        ensure
          Thread.current.thread_variable_set(:turns, Thread.current.thread_variable_get(:turns) + 1)
        end
      end
    end
  end

  # `theme_css:watch` (lib/tasks/theme_css.rake), one of the three processes
  # of bin/dev: one whole build, stamped when it succeeded (`build`), then
  # Tailwind's watcher on the same entry, with the stamp kept true beside it
  # (`keep_stamped`).
  #
  # IT DOES NOT END BECAUSE THE STYLESHEET DOES NOT BUILD. Foreman stops
  # every process of bin/dev when one of them ends, so a watch that raised
  # at its first build took the web server with it, and a person with a
  # half-written `@import` in their theme could not start the application
  # they were writing it in. Tailwind's own watcher does not stay either:
  # started on an entry that does not build it prints the error and exits
  # (seen with 4.3.3; a watcher that is already running when the stylesheet
  # breaks reports and stays). So the failure is said, once per failure,
  # under Tailwind's own words for it, which the executable has printed to
  # the same terminal; and the watch waits until a file of the theme or of
  # the default theme's styles has changed, and then tries again from the
  # whole build.
  #
  # The watcher ending well (its input closed, bin/dev stopped) ends the
  # watch; the watcher ending badly is taken as a build that failed, since
  # that is the one way it does by itself.
  #
  # A FOLDER THAT CANNOT BE LISTED IS WAITED OUT TOO, A TURN AT A TIME. The
  # theme's folder renamed or deleted, a file made unreadable, a link to
  # nothing: states that last until a person acts. Nothing is built then
  # (the build would fail before the executable started); the watch says it
  # once, by the error's class and without a path, and looks again every
  # `every` seconds. Every wait here sleeps BEFORE it looks: a wait that
  # compared first, with a look that could never equal the last, went round
  # thousands of times a second and printed its line each time.
  #
  # The stamp's keeper runs only beside the watcher, where nobody else hears
  # whether a build succeeded. While this loop builds and waits it is the
  # only builder and the only voice.
  def watch(folder, root:, executable:, blocks: [], every: 1, log: ->(line) { warn line })
    command = command(root: root, executable: executable)
    unreadable = nil

    loop do
      seen = sources_glance(folder, root: root, blocks: blocks)
      if seen.first == UNREADABLE
        _, why, type = seen
        unless unreadable == seen
          what = type ? "the stylesheet of the block type #{type}" : "the theme folder"
          log.call("theme_css:watch: #{what} cannot be read (#{why}). The watch goes on, and looks again until it can be.")
        end
        unreadable = seen
        sleep every
        next
      end
      unreadable = nil

      break if build_for_watch(folder, root: root, executable: executable, blocks: blocks) && watched(folder, command, root: root, blocks: blocks, every: every, log: log)

      log.call("theme_css:watch: the public stylesheet did not build; what Tailwind said of it is above. The watch goes on, " \
               "and builds again when a file of the theme or of the default theme's styles changes.")
      loop do
        sleep every
        break unless sources_glance(folder, root: root, blocks: blocks) == seen
      end
    end
  end

  # Tailwind's watcher, with the stamp kept true beside it for as long as it
  # runs. Answers how the watcher ended, as `system` does.
  def watched(folder, command, root:, every:, log:, blocks: [])
    keeper = keep_stamped(folder, root: root, blocks: blocks, every: every, log: log, build: -> { system(*command, out: File::NULL, err: File::NULL) })
    system(*command, "-w")
  ensure
    keeper&.kill
  end

  # `build`, answering whether it succeeded: a failed executable is the
  # watch's to say and to wait out, not an exception's.
  def build_for_watch(folder, root:, executable:, blocks: [])
    build(folder, root: root, executable: executable, blocks: blocks)
    true
  rescue RuntimeError, SystemCallError, ThemeFolder::Invalid, MissingStylesheet
    false
  end

  # What the build reads, without reading a file: the theme's folder
  # (`ThemeFolder#glance`), the default theme's stylesheets and each type's, by name,
  # size and time. A folder that cannot be listed is `[UNREADABLE, the
  # error's class, nil]`, and a type's stylesheet that cannot be read
  # `[UNREADABLE, the error's class, the type's name]`: the same answer for
  # as long as the same thing is wrong, so two looks at it are equal and a
  # wait on it waits, and the watch says whose file it is.
  UNREADABLE = :unreadable

  def sources_glance(folder, root:, blocks: [])
    sheets = blocks.filter_map do |block|
      next unless block.stylesheet

      sheet = Pathname(block.stylesheet).realpath
      status = File.stat(sheet)
      [ sheet.to_s, status.size, status.mtime.to_f ]
    rescue SystemCallError => error
      return [ UNREADABLE, error.class, block.type || block.stylesheet.to_s ]
    end
    files = Dir.glob(Pathname(root).join(DEFAULT).dirname.join("**/*").to_s)
    styles = files.uniq.sort.filter_map do |file|
      status = File.stat(file)
      [ file, status.size, status.mtime.to_f ] if status.file?
    end
    [ folder.glance, (styles + sheets).uniq.sort ]
  rescue SystemCallError, ThemeFolder::Invalid => error
    [ UNREADABLE, error.class, nil ]
  end

  def current_entry?(folder, root:, blocks: [])
    path = Pathname(root).join(ENTRY)
    path.file? && path.read == entry(folder, root: root, blocks: blocks)
  end
end
