# Run using bin/ci: what CI runs for a pull request (.github/workflows/ci.yml),
# one step after another on this machine. The browser tests want a quiet
# machine and, on a laptop, a cap on their workers (`PARALLEL_WORKERS=6
# bin/ci`, docs/reference/writing-tests.md). The changelog guard compares
# with origin/main, so fetch it first.

CI.run do
  # Gems, the development database, and the stylesheets.
  step "Setup", "bin/setup --skip-server"
  step "Setup: test database", "bin/rails db:test:prepare"

  step "Style: Ruby", "bin/rubocop"
  step "Changelog guard", "bin/changelog-guard origin/main"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Tests: Rails", "bin/rails test"
  step "Tests: Browser", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # After the tests, never beside them: it writes app/assets/builds, which
  # every public test reads, and builds the default stylesheet again on its
  # way out.
  step "Theme: build and start under a theme", "bin/theme-build-check"
end
