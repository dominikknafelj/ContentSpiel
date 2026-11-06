require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

# bin/changelog-guard BASE_REF: a change to a guarded file (the contract ledger,
# the plugin hooks, a migration) needs a line under "## Unreleased" in
# CHANGELOG.md, and a new migration its version under "### Migrations" there. Run on a
# throwaway repository, so no commit of this one (signed through 1Password) is
# made or read.
class ChangelogGuardTest < ActiveSupport::TestCase
  GUARD = Rails.root.join("bin/changelog-guard").to_s
  LEDGER = "test/support/contract_ledger.rb"
  MIGRATION = "db/migrate/20260101000000_old.rb"
  CHANGELOG = "# Changelog\n\n## Unreleased\n\n- Something.\n\n## 0.1.0\n\n- Older.\n"

  test "a ledger change with no changelog change fails and names the ledger" do
    in_repo do |git|
      write LEDGER, "# changed\n"
      git.call "commit", "-am", "ledger"
      out, status = run_guard
      assert_not status.success?
      assert_includes out, LEDGER
    end
  end

  test "a plugin hooks change is guarded too" do
    in_repo do |git|
      write "lib/content_spiel/plugins.rb", "# changed\n"
      git.call "commit", "-am", "hooks"
      out, status = run_guard
      assert_not status.success?
      assert_includes out, "lib/content_spiel/plugins.rb"
    end
  end

  test "a line added under Unreleased lets it pass" do
    in_repo do |git|
      write LEDGER, "# changed\n"
      write "CHANGELOG.md", CHANGELOG.sub("- Something.\n", "- Something.\n- New.\n")
      git.call "commit", "-am", "ledger and changelog"
      _out, status = run_guard
      assert status.success?
    end
  end

  test "a changelog line added under an older release does not count" do
    in_repo do |git|
      write LEDGER, "# changed\n"
      write "CHANGELOG.md", CHANGELOG.sub("- Older.\n", "- Older.\n- Late.\n")
      git.call "commit", "-am", "ledger and old changelog"
      out, status = run_guard
      assert_not status.success?
      assert_includes out, LEDGER
    end
  end

  test "a changed migration is guarded too" do
    in_repo do |git|
      write MIGRATION, "# changed\n"
      git.call "commit", "-am", "migration"
      out, status = run_guard
      assert_not status.success?
      assert_includes out, MIGRATION
    end
  end

  test "a new migration needs its version under ### Migrations in Unreleased" do
    in_repo do |git|
      added = "db/migrate/20261106090000_add_thing.rb"
      write added, "# new\n"
      write "CHANGELOG.md", CHANGELOG.sub("- Something.\n", "- Something.\n- Added a thing.\n")
      git.call "add", "."
      git.call "commit", "-qm", "migration with a line elsewhere"
      out, status = run_guard
      assert_not status.success?, "a line outside ### Migrations is not enough"
      assert_includes out, "not named under \"### Migrations\""
      assert_includes out, added

      write "CHANGELOG.md", CHANGELOG.sub("- Something.\n", "- Something.\n\n### Migrations needing action\n\n- `20261106090000` needs a person.\n")
      git.call "commit", "-qam", "under needing action"
      _out, status = run_guard
      assert_not status.success?, "Migrations needing action is not Migrations"

      write "CHANGELOG.md", CHANGELOG.sub("- Something.\n", "- Something.\n\n### Migrations\n\n- `20261106090000_add_thing` adds a column.\n")
      git.call "commit", "-qam", "under Migrations"
      out, status = run_guard
      assert status.success?, out
    end
  end

  test "a change of another file passes" do
    in_repo do |git|
      write "app/other.rb", "# changed\n"
      git.call "commit", "-am", "other"
      _out, status = run_guard
      assert status.success?
    end
  end

  private

  # A repository with a main branch holding the guarded files and a changelog,
  # and a work branch checked out from it; the block makes the work branch's commits.
  def in_repo
    Dir.mktmpdir do |dir|
      @dir = dir
      git = ->(*args) {
        out, status = Open3.capture2e("git", "-C", dir, *args)
        assert status.success?, "git #{args.join(' ')}: #{out}"
        out
      }
      git.call "init", "-q", "-b", "main"
      git.call "config", "user.name", "Test"
      git.call "config", "user.email", "test@example.com"
      git.call "config", "commit.gpgsign", "false"
      write LEDGER, "# ledger\n"
      write "lib/content_spiel/plugins.rb", "# hooks\n"
      write "app/other.rb", "# other\n"
      write MIGRATION, "# old\n"
      write "CHANGELOG.md", CHANGELOG
      git.call "add", "."
      git.call "commit", "-q", "-m", "base"
      git.call "checkout", "-q", "-b", "work"
      yield git
    end
  end

  def write(path, content)
    full = File.join(@dir, path)
    FileUtils.mkdir_p File.dirname(full)
    File.write full, content
  end

  def run_guard
    Open3.capture2e(GUARD, "main", chdir: @dir)
  end
end
