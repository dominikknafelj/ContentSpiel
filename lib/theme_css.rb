require "pathname"
require "fileutils"

# The public stylesheet's build (theming spec §4). ONE stylesheet, built from
# an entry file this module writes:
#
#   @import "<default theme>/theme.css";              tokens, base, prose, sections, the default templates' utilities
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
# Both imports come before the `@source` lines: an `@import` after another
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

  module_function

  def entry(folder, root:)
    from = Pathname(root).join(ENTRY).dirname
    relative = ->(path) { Pathname(path).relative_path_from(from).to_s }
    default = Pathname(root).join(DEFAULT)

    imports = [ default ]
    sources = [ default.dirname ]
    if folder.configured?
      theme = folder.path.realpath
      if (stylesheet = folder.stylesheet&.relative_path_from(folder.path))
        imports << theme.join(stylesheet)
        sources << theme.join(stylesheet).dirname
      end
      sources.concat(%w[views components].map { |name| theme.join(name) }.select(&:directory?))
    end

    lines = imports.map { |path| %(@import "#{relative.(path)}";) } + sources.map { |path| %(@source "#{relative.(path)}";) }
    lines.join("\n") + "\n"
  end

  def write_entry(folder, root:)
    path = Pathname(root).join(ENTRY)
    FileUtils.mkdir_p(path.dirname)
    path.write(entry(folder, root: root))
    path
  end

  def command(root:, executable:)
    [ executable, "-i", File.join(root.to_s, ENTRY), "-o", File.join(root.to_s, OUTPUT), "--minify" ]
  end

  # `fingerprint` is handed in by a caller that has read it already and
  # must have THAT value written (`build`, `keep_stamped`): the folder can
  # change between two readings.
  def stamp!(folder, root:, fingerprint: folder.fingerprint)
    path = Pathname(root).join(ThemeFolder::STAMP)
    FileUtils.mkdir_p(path.dirname)
    path.write("#{fingerprint}\n")
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
  def build(folder, root:, executable:)
    fingerprint = folder.fingerprint
    unstamp!(root: root)
    write_entry(folder, root: root)
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
  def keep_stamped(folder, root:, build:, every: 1, log: ->(line) { warn line })
    return nil unless folder.configured?

    mine = ThemeFolder.stamp(root)
    seen = [ folder.glance, mine ]
    said = false

    Thread.new do
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
            write_entry(folder, root: root) unless current_entry?(folder, root: root)
            if build.call
              stamp!(folder, root: root, fingerprint: fingerprint)
              mine = fingerprint
            else
              unstamp!(root: root)
              mine = nil
            end
          end
          seen = [ look, ThemeFolder.stamp(root) ]
        rescue StandardError => error
          log.call("theme_css:watch: the stylesheet's stamp could not be kept (#{error.class}); it will be tried again") unless said
          said = true
        end
      end
    end
  end

  def current_entry?(folder, root:)
    path = Pathname(root).join(ENTRY)
    path.file? && path.read == entry(folder, root: root)
  end
end
