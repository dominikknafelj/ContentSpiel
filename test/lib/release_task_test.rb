require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

# `release:prepare[V]` (lib/tasks/release.rake) is ContentSpiel::Release on a
# folder. Each test copies the repository's two files into a throwaway git
# repository, so no commit of this one (signed through 1Password) is made and
# nothing real is rewritten.
class ReleaseTaskTest < ActiveSupport::TestCase
  Release = ContentSpiel::Release
  TODAY = Date.new(2026, 11, 5)
  VERSION_RB = "lib/content_spiel/version.rb".freeze

  test "a release rewrites VERSION and dates the unreleased section under a fresh empty one" do
    in_repo do |root, _git|
      write root, "CHANGELOG.md", "# Changelog\n\n## Unreleased\n\n### Added\n\n- Something.\n\n## 0.1.0 (2026-10-01)\n\n- Older.\n"
      commit_all root
      commands = Release.new(root, today: TODAY).prepare("0.2.0")

      assert_equal "# Changelog\n\n## Unreleased\n\n## 0.2.0 (2026-11-05)\n\n### Added\n\n- Something.\n\n## 0.1.0 (2026-10-01)\n\n- Older.\n",
        File.read("#{root}/CHANGELOG.md")
      assert_includes File.read("#{root}/#{VERSION_RB}"), %(VERSION = "0.2.0")
      assert_equal [ "git switch -c release-0.2.0",
        "git commit -am 'chore: release 0.2.0'",
        "git push -u origin release-0.2.0",
        "gh pr create --title 'Release 0.2.0' --body 'Cuts 0.2.0: merging this tags v0.2.0 and publishes the image.'" ], commands
    end
  end

  test "it writes only the two files and makes no tag, branch or commit" do
    in_repo do |root, git|
      commit_all root
      head = git.call("rev-parse", "HEAD")
      Release.new(root, today: TODAY).prepare("0.2.0")
      assert_equal head, git.call("rev-parse", "HEAD")
      assert_equal "", git.call("tag", "-l")
      assert_equal "main", git.call("branch", "--show-current")
      assert_equal [ "M CHANGELOG.md", "M #{VERSION_RB}" ], git.call("status", "--porcelain").lines.map(&:strip).sort
    end
  end

  test "a dirty tree is refused and nothing is written" do
    in_repo do |root, _git|
      commit_all root
      write root, "stray.txt", "x"
      assert_refused root, "0.2.0", /not clean/
      assert_includes File.read("#{root}/#{VERSION_RB}"), '"0.1.0"'
    end
  end

  test "a version that is not greater than the current one is refused" do
    in_repo do |root, _git|
      commit_all root
      assert_refused root, "0.1.0", /not greater/
      assert_refused root, "0.0.9", /not greater/
    end
  end

  test "versions compare as numbers, not as text" do
    in_repo do |root, _git|
      write root, VERSION_RB, File.read("#{root}/#{VERSION_RB}").sub('"0.1.0"', '"0.10.0"')
      commit_all root
      assert_refused root, "0.9.0", /not greater/
      assert_nothing_raised { Release.new(root, today: TODAY).prepare("0.11.0") }
    end
  end

  test "something that is not a MAJOR.MINOR.PATCH number is refused" do
    in_repo do |root, _git|
      commit_all root
      [ "1", "1.2", "v1.2.3", "1.2.3-rc1", "" ].each { |bad| assert_refused root, bad, /not a release number/ }
    end
  end

  test "an existing tag is refused" do
    in_repo do |root, git|
      commit_all root
      git.call "tag", "v0.2.0"
      assert_refused root, "0.2.0", /tag v0\.2\.0 already exists/
    end
  end

  test "an empty Unreleased section is refused" do
    in_repo do |root, _git|
      write root, "CHANGELOG.md", "# Changelog\n\n## Unreleased\n\n## 0.1.0 (2026-10-01)\n\n- Older.\n"
      commit_all root
      assert_refused root, "0.2.0", /empty/
    end
  end

  test "an Unreleased section of sub-headings only is empty" do
    in_repo do |root, _git|
      write root, "CHANGELOG.md", "# Changelog\n\n## Unreleased\n\n### Added\n\n### Fixed\n\n## 0.1.0 (2026-10-01)\n\n- Older.\n"
      commit_all root
      assert_refused root, "0.2.0", /empty/
    end
  end

  test "a CRLF changelog is rewritten like an LF one and keeps its line endings" do
    in_repo do |root, _git|
      write root, "CHANGELOG.md", "# Changelog\r\n\r\n## Unreleased\r\n\r\n- Something.\r\n"
      commit_all root
      Release.new(root, today: TODAY).prepare("0.2.0")
      assert_equal "# Changelog\r\n\r\n## Unreleased\r\n\r\n## 0.2.0 (2026-11-05)\r\n\r\n- Something.\r\n", File.binread("#{root}/CHANGELOG.md")
    end
  end

  test "a changelog without the heading is refused, not left unchanged" do
    in_repo do |root, _git|
      write root, "CHANGELOG.md", "# Changelog\n\n## Unreleased changes\n\n- Something.\n"
      commit_all root
      assert_refused root, "0.2.0", /no ## Unreleased/
      assert_includes File.read("#{root}/#{VERSION_RB}"), '"0.1.0"'
    end
  end

  test "notes are one version's section, up to the next heading" do
    changelog = "# Changelog\n\n## Unreleased\n\n- Next.\n\n## 0.2.0 (2026-11-05)\n\n### Added\n\n- Two.\n\n## 0.1.0 (2026-10-01)\n\n- One.\n"
    assert_equal "### Added\n\n- Two.", Release.notes(changelog, "0.2.0")
    assert_equal "- One.", Release.notes(changelog, "0.1.0")
    assert_raises(Release::Refused) { Release.notes(changelog, "0.3.0") }
    assert_raises(Release::Refused) { Release.notes(changelog, "0.2") }
  end

  test "a section with nothing but whitespace has no notes: refused, as a missing one is" do
    changelog = "# Changelog\n\n## 0.2.0 (2026-11-05)\n\n  \n\t\n\n## 0.1.0 (2026-10-01)\n\n- One.\n"
    error = assert_raises(Release::Refused) { Release.notes(changelog, "0.2.0") }
    assert_equal "CHANGELOG.md's section for 0.2.0 is empty", error.message
    assert_raises(Release::Refused) { Release.notes(changelog, "0.2.0", ordered: true) }
    assert_equal "- One.", Release.notes(changelog, "0.1.0")
  end

  test "ordered notes put Breaking, Theme contract, Removed, Migrations needing action and Environment first, in that order" do
    changelog = <<~MD
      ## 0.2.0 (2026-11-05)

      Opening line.

      ### Added

      - Added.

      ### Environment

      - Env.

      ### For a gem or an outside caller

      - Gem.

      ### Migrations needing action

      - Act.

      ### Migrations

      - Migrate.

      ### Removed

      - Gone.

      ### Theme contract

      - Contract.

      ### Breaking

      - Broke.
    MD
    headings = Release.notes(changelog, "0.2.0", ordered: true).scan(/^### (.*)$/).flatten

    assert_equal [ "Breaking", "Theme contract", "Removed", "Migrations needing action", "Environment",
                   "Added", "For a gem or an outside caller", "Migrations" ], headings
    assert Release.notes(changelog, "0.2.0", ordered: true).start_with?("Opening line.")
    assert_equal Release.notes(changelog, "0.2.0").scan(/^### (.*)$/).flatten.first, "Added", "unordered is the file's order"
  end

  # release.yml's notes step is this line, run with no bundle: the GitHub
  # Release carries the ordered section, and an empty one stops the run.
  test "the release workflow's notes are the ordered ones, and an empty section fails its step" do
    workflow = File.read(Rails.root.join(".github/workflows/release.yml"))
    assert_includes workflow, "ContentSpiel::Release.notes(File.read(\"CHANGELOG.md\"), ARGV.fetch(0), ordered: true)"
    assert_not_includes workflow, "-s release-notes.md", "the check is the method's own, not the file's size"

    Dir.mktmpdir do |dir|
      File.write("#{dir}/CHANGELOG.md", "## 0.2.0 (2026-11-05)\n\n### Added\n\n- A.\n\n### Breaking\n\n- B.\n\n## 0.1.0 (2026-10-01)\n\n\n")
      script = "puts ContentSpiel::Release.notes(File.read(\"CHANGELOG.md\"), ARGV.fetch(0), ordered: true)"
      ruby = ->(version) { Bundler.with_unbundled_env { Open3.capture3("ruby", "-r", Rails.root.join("lib/content_spiel/release").to_s, "-e", script, version, chdir: dir) } }

      out, _err, status = ruby.("0.2.0")
      assert status.success?
      assert_operator out.index("### Breaking"), :<, out.index("### Added")
      _out, err, status = ruby.("0.1.0")
      assert_not status.success?
      assert_includes err, "CHANGELOG.md's section for 0.1.0 is empty"
    end
  end

  test "the rake task prints the commands and refuses with a message and a failing exit" do
    in_repo do |root, _git|
      commit_all root
      out, status = rake(root, "release:prepare[0.1.0]")
      assert_not status.success?
      assert_match(/not greater/, out)
      out, status = rake(root, "release:prepare[0.2.0]")
      assert status.success?, out
      assert_includes out, "git switch -c release-0.2.0"
      assert_includes out, "gh pr create"
    end
  end

  private

  def assert_refused(root, version, pattern)
    error = assert_raises(Release::Refused) { Release.new(root, today: TODAY).prepare(version) }
    assert_match pattern, error.message
  end

  def rake(root, task)
    # The task only needs ContentSpiel::Release and Rails.root, so it runs from
    # a bare Rakefile of its own: no database, no application boot.
    # The Rakefile is kept outside the throwaway repository, which must stay clean.
    Dir.mktmpdir do |other|
      File.write("#{other}/Rakefile", "require 'pathname'\nmodule Rails; def self.root = Pathname.new(#{root.inspect}); end\nload #{Rails.root.join('lib/tasks/release.rake').to_s.inspect}\n")
      Open3.capture2e("rake", "-f", "#{other}/Rakefile", task, chdir: root.to_s)
    end
  end

  def in_repo
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      FileUtils.mkdir_p(root.join("lib/content_spiel"))
      # The real file's shape, at the number these tests start from.
      File.write(root.join(VERSION_RB), File.read(Rails.root.join(VERSION_RB)).sub(/VERSION = "[^"]*"/, 'VERSION = "0.1.0"'))
      File.write(root.join("CHANGELOG.md"), "# Changelog\n\n## Unreleased\n\n- Something.\n")
      git = lambda do |*args|
        out, status = Open3.capture2e("git", "-C", dir, "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false",
          "-c", "user.name=Test", "-c", "user.email=test@example.com", *args)
        raise "git #{args.join(' ')}: #{out}" unless status.success?
        out.strip
      end
      git.call "init", "-q", "-b", "main"
      # No background work in the throwaway repository: auto maintenance and gc
      # take .git/objects/maintenance.lock, which the folder's removal raced.
      %w[maintenance.auto=false gc.auto=0 core.fsmonitor=false].each { |setting| git.call "config", *setting.split("=") }
      yield root.to_s, git
    end
  end

  def commit_all(root)
    git = ->(*args) { system("git", "-C", root, "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=t@example.com", *args, out: File::NULL, exception: true) }
    git.call "add", "-A"
    git.call "commit", "-q", "-m", "start"
  end

  def write(root, path, content)
    File.write("#{root}/#{path}", content)
  end
end
