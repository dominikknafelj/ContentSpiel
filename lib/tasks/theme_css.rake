# tailwindcss-rails 4.6 builds exactly one entry (app/assets/tailwind/
# application.css). The public theme is a second, independent entry (spec §9),
# built with the same Tailwind executable and chained onto
# `tailwindcss:build` -- so assets:precompile, test:prepare, CI and the Docker
# build all produce both stylesheets.
require "tailwindcss/ruby"

module ThemeCss
  module_function

  def command
    [
      Tailwindcss::Ruby.executable,
      "-i", Rails.root.join("app/assets/tailwind/themes/default/theme.css").to_s,
      "-o", Rails.root.join("app/assets/builds/theme-default.css").to_s,
      "--minify"
    ]
  end
end

namespace :theme_css do
  desc "Build the public default theme stylesheet"
  task build: :environment do
    system(*ThemeCss.command, exception: true)
  end

  desc "Watch and rebuild the public default theme stylesheet"
  task watch: :environment do
    system(*ThemeCss.command, "-w", exception: true)
  end
end

Rake::Task["tailwindcss:build"].enhance { Rake::Task["theme_css:build"].invoke }
