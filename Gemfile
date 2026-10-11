source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.7"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
# Pinned to an exact version: CS Studio's save footer
# (app/javascript/controllers/admin/saving/save_bar_controller.js) and write queue
# (app/javascript/saving/queue.js) rely on Turbo internals -- its history
# bookkeeping and popstate listener, the current visit, the order its events
# come in. An upgrade is a deliberate change: bump the pin, then rerun their
# system tests (test/system/save_bar_test.rb, test/system/admin/autosave_test.rb,
# changed_elsewhere_test.rb, blocks_test.rb) before anything else.
gem "turbo-rails", "2.0.23"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Pin below json 3.x: its JSON.parse(source, options) no longer accepts a
# positional options hash, which breaks ActiveSupport::JSON.decode (used by
# signed/encrypted cookies, e.g. the session cookie in Authentication#find_session_by_cookie)
# under activesupport 8.1.3.1 on Ruby 3.4.9.
gem "json", "< 4.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
#
# image_processing 2.x no longer bundles a backend gem -- Rails' default
# variant processor is vips, so that backend has to be declared explicitly.
gem "image_processing", "~> 2.2"
gem "ruby-vips", "~> 2.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "cuprite"

  # Code coverage, on request: `COVERAGE=1 bin/rails test` writes
  # coverage/index.html (test/test_helper.rb) [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false
end

# Translates model content per locale [https://github.com/shioyama/mobility].
# Every translated attribute, rich-text bodies included, uses its jsonb
# backend (config/initializers/mobility.rb).
gem "mobility", "~> 1.3"

# Parses/renders CommonMark for `RichText::Markdown` (design spec §3.4) --
# MCP reads and writes rich-text bodies as Markdown, converted to and from
# the Tiptap/ProseMirror JSON `RichText::Document` wraps
# [https://github.com/gjtorikian/commonmarker]. Only its AST (`Commonmarker
# .parse`) is walked -- `RichText::Markdown` never calls its HTML renderer,
# so the gem's own `unsafe`/raw-HTML rendering path is never reached.
gem "commonmarker", "~> 2.10"

# Stores the page tree in a closure table, so ancestor/descendant lookups for
# the navigation are one join deep regardless of nesting
# [https://github.com/closuretree/closure_tree].
gem "closure_tree", "~> 9.8"

# Builds public/sitemap.xml from the published page tree. The sitemap itself is
# defined in config/sitemap.rb and written by `rake sitemap:create`
# [https://github.com/kjvarga/sitemap_generator].
gem "sitemap_generator", "~> 7.1"

# OpenTelemetry tracing (config/initializers/opentelemetry.rb). The otlp
# exporter is bundled now, dormant, so switching from the console exporter
# used in dev/test to a real backend later is an env var
# (OTEL_EXPORTER_OTLP_ENDPOINT), not a new gem.
gem "opentelemetry-sdk", "~> 1.13"

gem "opentelemetry-instrumentation-all", "~> 0.97"

gem "opentelemetry-exporter-otlp", "~> 0.37"


# The official Ruby SDK for MCP servers (design spec section 10) --
# [https://github.com/modelcontextprotocol/ruby-sdk].
gem "mcp", "~> 1.6"

gem "rack-attack", "~> 6.8"

gem "view_component", "~> 4.15"

gem "lookbook", "~> 2.3", groups: [ :development, :test ]

# The official Anthropic SDK -- the built-in AI translation provider
# (`AI::Providers::Anthropic`, translation helpers spec §6). Only ever
# constructed when a site has an AI key configured; tests inject a fake
# client and never reach the network.
gem "anthropic"
