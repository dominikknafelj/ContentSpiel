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

  def stamp!(folder, root:)
    path = Pathname(root).join(ThemeFolder::STAMP)
    FileUtils.mkdir_p(path.dirname)
    path.write("#{folder.fingerprint}\n")
  end

  # For the watch (lib/tasks/theme_css.rake): a thread that asks the folder
  # for its fingerprint once every `every` seconds and, when it has changed,
  # writes the stamp again. Tailwind's watcher rebuilds the stylesheet on a
  # change by itself; this keeps what the stamp says true, so that System
  # status warns in development only about a stylesheet nobody is building.
  #
  # It follows the folder and nothing else: the stamp is rewritten only
  # while it is still the one this watch last knew. A stamp somebody else
  # wrote since (`bin/rails test` builds the default theme's stylesheet into
  # the same app/assets/builds, entry file and all) is left as it is, because
  # the stylesheet is then theirs too, and System status goes on saying so
  # until it is built again for the theme.
  #
  # nil without a theme folder: the default theme's fingerprint never
  # changes. A folder that cannot be read for a moment (a file half
  # written, a link not yet made) is asked again at the next turn.
  def keep_stamped(folder, root:, every: 1)
    return nil unless folder.configured?

    known = folder.fingerprint
    Thread.new do
      loop do
        sleep every
        begin
          now = folder.fingerprint
          next if now == known

          stamp!(folder, root: root) if ThemeFolder.stamp(root) == known
          known = now
        rescue ThemeFolder::Invalid, SystemCallError
          next
        end
      end
    end
  end
end
