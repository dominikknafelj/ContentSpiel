# tailwindcss-rails builds exactly one entry (app/assets/tailwind/
# application.css). The public stylesheet is a second, independent entry
# (spec §9), built with the same Tailwind executable and chained onto
# `tailwindcss:build` -- so assets:precompile, test:prepare, CI and the Docker
# build all produce both stylesheets. What the entry holds, and why, is
# `ThemeCss` (lib/theme_css.rb): the default theme's styles, then each
# registered block type's stylesheet (`BlockTypes.theme_css_blocks`), then the
# styles of the theme THEME_PATH names.
require "tailwindcss/ruby"

namespace :theme_css do
  desc "Build the public stylesheet: the default theme's styles, then the theme's (THEME_PATH)"
  task build: :environment do
    # The test environment builds the default theme's stylesheet into the
    # place development uses (lib/theme_css.rb). Said here, in the terminal
    # of whoever ran the tests, when it replaces a theme's.
    replaced = ThemeFolder.stamp(Rails.root)
    ThemeCss.build(ThemeFolder.current, root: Rails.root, executable: Tailwindcss::Ruby.executable,
                    blocks: BlockTypes.theme_css_blocks)
    if Rails.env.test? && replaced && replaced != ThemeFolder::DEFAULT_FINGERPRINT
      warn "[ContentSpiel] The public stylesheet was built for a theme and is now the default theme's (the tests build it). " \
           "For development under the theme, run bin/rails tailwindcss:build with THEME_PATH set, or start bin/dev again."
    end
  end

  # One whole build, then Tailwind's watcher on the same entry with the
  # stamp kept true beside it; a stylesheet that does not build is said and
  # waited out, never the end of bin/dev (`ThemeCss.watch`).
  desc "Watch and rebuild the public stylesheet"
  task watch: :environment do
    ThemeCss.watch(ThemeFolder.current, root: Rails.root, executable: Tailwindcss::Ruby.executable,
                    blocks: BlockTypes.theme_css_blocks)
  end
end

Rake::Task["tailwindcss:build"].enhance { Rake::Task["theme_css:build"].invoke }
