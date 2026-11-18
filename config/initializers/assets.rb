# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Production serves the app's own JavaScript without its comments
# (lib/content_spiel/js_comment_compiler.rb, lib/content_spiel/js_comment_stripper.rb):
# the image's `assets:precompile` runs under RAILS_ENV=production (the
# Dockerfile's ENV) and writes the stripped files into public/assets, while
# development (`bin/dev`) and test never register the compiler and serve
# every file exactly as written. Line breaks are kept, so a production stack
# trace's line numbers are the source's.
#
# Propshaft digests a file's SOURCE, not its compiled output, so the
# stripper's revision is part of the version: the same source stripped by
# other rules gets a new address, never one a browser cached for a year.
# Here and not in config/environments/production.rb, which runs before this
# file and would have its version overwritten by the line above; Propshaft's
# assembly reads the compilers and the version on first use, after the
# initializers.
if Rails.env.production?
  Rails.application.config.assets.version += "-js#{ContentSpiel::JsCommentStripper::REVISION}"
  Rails.application.config.assets.compilers << [ "text/javascript", ContentSpiel::JsCommentCompiler ]
end
