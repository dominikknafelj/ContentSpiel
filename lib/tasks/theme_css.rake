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
    # The test environment builds the default theme's stylesheet into the
    # place development uses (lib/theme_css.rb). Said here, in the terminal
    # of whoever ran the tests, when it replaces a theme's.
    replaced = ThemeFolder.stamp(Rails.root)
    ThemeCss.build(ThemeFolder.current, root: Rails.root, executable: Tailwindcss::Ruby.executable)
    if Rails.env.test? && replaced && replaced != ThemeFolder::DEFAULT_FINGERPRINT
      warn "[ContentSpiel] The public stylesheet was built for a theme and is now the default theme's (the tests build it). " \
           "For development under the theme, run bin/rails tailwindcss:build with THEME_PATH set, or start bin/dev again."
    end
  end

  # One whole build first, stamped when it succeeded (`ThemeCss.build`), and
  # then Tailwind's watcher on the same entry. While it runs, the stamp is
  # kept true by `ThemeCss.keep_stamped`: when the theme's folder changed it
  # builds once more itself, quietly, and stamps what it built, because the
  # watcher's own rebuild tells nobody whether it succeeded.
  desc "Watch and rebuild the public stylesheet"
  task watch: :environment do
    folder = ThemeFolder.current
    command = ThemeCss.command(root: Rails.root, executable: Tailwindcss::Ruby.executable)
    ThemeCss.build(folder, root: Rails.root, executable: Tailwindcss::Ruby.executable)
    ThemeCss.keep_stamped(folder, root: Rails.root, build: -> { system(*command, out: File::NULL, err: File::NULL) })
    system(*command, "-w", exception: true)
  end
end

Rake::Task["tailwindcss:build"].enhance { Rake::Task["theme_css:build"].invoke }
