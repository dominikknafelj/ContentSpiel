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

# Inside `to_prepare`, as every registry is (config/initializers/types.rb):
# its first run is the boot, so a folder that is not a theme stops the boot;
# and after a code reload the Theme is built again, against the freshly
# loaded component classes.
Rails.application.config.to_prepare do
  Theme.current = Theme.load(ThemeFolder.current)
end
