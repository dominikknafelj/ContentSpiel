# The site's theme (theming spec §1): what the CMS does with the folder
# THEME_PATH names when the application starts. `lib/theme_folder.rb` reads
# and checks the folder; `app/values/theme.rb` is the runtime side.
folder = ThemeFolder.current

# A changed template, stylesheet or script of the theme reloads the
# application in development, as a change under app/ does: the reload runs
# `to_prepare` below, which builds a new Theme with the folder's new
# fingerprint and new subclasses for the components it replaces. (Templates
# under <theme>/views alone would need none of this: Action View watches
# every view path.)
Rails.application.config.watchable_dirs[folder.path.to_s] = %w[erb css js] if folder.configured?

# The theme's images and fonts are named in its stylesheet and templates by
# file name, and Propshaft writes the digested address; its `javascript`
# folder is where a controller is served from (`ThemeFolder#pins`). Appended,
# never put first: a theme adds assets, and one named like an asset of the
# CMS's own stops the boot before the order could matter (`Theme::Check`).
folder.asset_paths.each { |directory| Rails.application.config.assets.paths << directory.to_s }

# Inside `to_prepare`, as every registry is (config/initializers/types.rb):
# its first run is the boot, so a folder that is not a theme stops the boot;
# and after a code reload the Theme is built again, against the freshly
# loaded component classes.
#
# The first run raises and every later one does not (`Theme.prepare` says
# why: a raise in a reload's prepare chain leaves the registries of the
# blocks after this one unprepared). `after_initialize` runs once, after the
# boot's own prepare, so `booted` is false for exactly that first run.
booted = false
Rails.application.config.after_initialize { booted = true }

Rails.application.config.to_prepare do
  Theme.current = Theme.prepare(ThemeFolder.current, reload: booted)
  Rails.logger.error("[ContentSpiel] #{Theme.current.refusal.message}") if Theme.current.refusal
end
