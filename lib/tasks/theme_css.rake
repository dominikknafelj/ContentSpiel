# tailwindcss-rails builds exactly one entry (app/assets/tailwind/
# application.css). The public stylesheet is a second, independent entry
# (spec §9), built with the same Tailwind executable and chained onto
# `tailwindcss:build` -- so assets:precompile, test:prepare, CI and the Docker
# build all produce both stylesheets. What the entry holds, and why, is
# `ThemeCss` (lib/theme_css.rb): the default theme's styles, then the styles
# of the theme THEME_PATH names.
require "tailwindcss/ruby"

namespace :theme_css do
  desc "Build the public stylesheet: the default theme's styles, then the theme's (THEME_PATH)"
  task build: :environment do
    folder = ThemeFolder.current
    ThemeCss.write_entry(folder, root: Rails.root)
    system(*ThemeCss.command(root: Rails.root, executable: Tailwindcss::Ruby.executable), exception: true)
    ThemeCss.stamp!(folder, root: Rails.root)
  end

  # The entry is written once, when the watch starts: a `components` folder
  # or a stylesheet a theme GAINS while it runs is in no line of it, and
  # needs the watch started again (as a new controller needs the server
  # started again, config/importmap.rb).
  #
  # The stamp is kept the theme's while the watch runs (`keep_stamped`):
  # Tailwind's own watcher builds again when a file of the theme changes,
  # and the folder's fingerprint changes with it, so a stamp written once
  # would say "built for another theme" on System status after the first
  # edit, about a stylesheet that is the theme's.
  desc "Watch and rebuild the public stylesheet"
  task watch: :environment do
    folder = ThemeFolder.current
    ThemeCss.write_entry(folder, root: Rails.root)
    ThemeCss.stamp!(folder, root: Rails.root)
    ThemeCss.keep_stamped(folder, root: Rails.root)
    system(*ThemeCss.command(root: Rails.root, executable: Tailwindcss::Ruby.executable), "-w", exception: true)
  end
end

Rake::Task["tailwindcss:build"].enhance { Rake::Task["theme_css:build"].invoke }
