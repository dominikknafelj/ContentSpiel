# The second theme's controllers in the TEST environment's import map
# (config/environments/test.rb adds this file to `config.importmap.paths`).
# The import map is drawn once when the application starts and the suite
# swaps themes in-process, so the pin is there from the start; it is made by
# the same `ThemeFolder#pins` that config/importmap.rb uses for a real theme.
pins = ThemeFolder.new(File.expand_path("plain", __dir__)).pins
pin_all_from pins[:dir], under: pins[:under], to: pins[:to], preload: pins[:preload]
