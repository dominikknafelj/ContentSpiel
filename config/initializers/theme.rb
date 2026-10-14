# The site's theme (theming spec §1): what the CMS does with the folder
# THEME_PATH names when the application starts. `lib/theme_folder.rb` reads
# and checks the folder; `app/values/theme.rb` is the runtime side.
folder = ThemeFolder.current

# A changed template, stylesheet or script of the theme reloads the
# application in development, as a change under app/ does: the reload runs
# `to_prepare` (its last lines are in config/initializers/types.rb), which builds a new Theme with the folder's new
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

# Prepared at the END of the registration block in config/initializers/types.rb,
# not here (block types spec, decision 6): the check reads the theme contract,
# and the contract's block lines are read from the registered types. An order
# written in one block is read; one that depended on these two files' names
# was not. What stays here is what is done once at boot (the watched folder,
# the asset paths above) and the flag that tells the boot's prepare from a
# reload's: `after_initialize` runs once, after the boot's own prepare, so the
# flag is false for exactly that first run (`Theme.prepare` says why the two
# differ).
Rails.application.config.x.theme_booted = false
Rails.application.config.after_initialize { Rails.application.config.x.theme_booted = true }
