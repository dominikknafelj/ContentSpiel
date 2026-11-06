require "test_helper"
require "tmpdir"
require "fileutils"
require Rails.root.join("lib/content_spiel/upgrade").to_s

# `contentspiel upgrade` (bin/contentspiel), whose work is
# `ContentSpiel::Upgrade`: tested on throwaway site folders, a changelog text
# written here and a check handed in as a lambda, so nothing starts the
# application.
class UpgradeTest < ActiveSupport::TestCase
  CHANGELOG = <<~MD.freeze
    # Changelog

    ## Unreleased

    ### Breaking

    - NEVER SHOWN: not released.

    ## 0.3.0 (2026-03-01)

    ### Added

    - Added three.

    ### Breaking

    - Broke three.

    ## 0.2.0 (2026-02-01)

    ### Environment

    - Env two.

    ### Migrations needing action

    - Migrate two.

    ### Theme contract

    - Contract two.

    ## 0.1.0 (2026-01-01)

    ### Added

    - Added one.
  MD

  NO_PROBLEMS = -> { [] }

  test "already on this version: says so and writes nothing" do
    in_site("0.3.0") do |site|
      result = upgrade(site, check: -> { flunk "the check is not run" }).run

      assert_equal 0, result.code
      assert_includes result.text, "already on ContentSpiel 0.3.0"
      assert_equal "0.3.0\n", pin(site)
    end
  end

  test "a pin that is not a release number is refused, stable included" do
    [ "latest", "1.2", "v1.2.3", "1.2.3-beta", "stable", "" ].each do |value|
      in_site(value) do |site|
        error = assert_raises(ContentSpiel::Upgrade::Refused, value) { upgrade(site).run }

        assert_includes error.message, "X.Y.Z"
        assert_equal "#{value}\n", pin(site)
      end
    end
  end

  test "a pin newer than this image is refused, naming which is newer" do
    in_site("0.4.0") do |site|
      error = assert_raises(ContentSpiel::Upgrade::Refused) { upgrade(site).run }

      assert_includes error.message, "0.4.0"
      assert_includes error.message, "newer than"
      assert_includes error.message, "0.3.0"
      assert_equal "0.4.0\n", pin(site)
    end
  end

  test "a folder with no pin or no theme is refused" do
    Dir.mktmpdir do |dir|
      assert_raises(ContentSpiel::Upgrade::Refused) { upgrade(dir).run }
      File.write(File.join(dir, ".contentspiel-version"), "0.1.0\n")
      assert_raises(ContentSpiel::Upgrade::Refused) { upgrade(dir).run }
    end
  end

  test "a failing check shows the notes then the check, and leaves the pin" do
    in_site("0.1.0") do |site|
      result = upgrade(site, check: -> { [ "views/blocks/_card.html.erb draws @page", "theme.yml is wrong" ] }).run

      assert_equal 1, result.code
      assert_equal "0.1.0\n", pin(site)
      assert_operator result.text.index("Release notes"), :<, result.text.index("Theme check")
      assert_includes result.text, "1. views/blocks/_card.html.erb draws @page"
      assert_includes result.text, "2. theme.yml is wrong"
      assert_includes result.text, "2 problems"
      assert_includes result.text, "The version was not moved"
      assert_not_includes result.text, "Next steps"
      assert_empty Dir.children(site).grep(/tmp/)
    end
  end

  test "success moves the pin, orders the sections oldest first, and prints the next steps" do
    in_site("0.1.0") do |site|
      result = upgrade(site).run
      text = result.text

      assert_equal 0, result.code
      assert_equal "0.3.0\n", pin(site)
      assert_operator text.index("## 0.2.0"), :<, text.index("## 0.3.0")
      assert_not_includes text, "## 0.1.0"
      assert_not_includes text, "NEVER SHOWN"
      assert_operator text.index("Release notes"), :<, text.index("Theme check")
      assert_operator text.index("Theme check"), :<, text.index("Next steps")
      assert_includes text, "contentspiel upgrade moved this site from 0.1.0 to 0.3.0"
      assert_includes text, "kamal deploy"
      assert_includes text, ".contentspiel-version"
      assert_includes text, "docker volume rm demo-dev_builds_0_1_0"
      assert_empty Dir.children(site).grep(/tmp/)
    end
  end

  test "within a section, Breaking and Theme contract come first, then the rest in file order" do
    in_site("0.1.0") do |site|
      text = upgrade(site).run.text
      two = text[text.index("## 0.2.0")...text.index("## 0.3.0")]

      assert_operator two.index("### Theme contract"), :<, two.index("### Environment")
      assert_operator two.index("### Environment"), :<, two.index("### Migrations needing action")

      three = text[text.index("## 0.3.0")..]
      assert_operator three.index("### Breaking"), :<, three.index("### Added")
    end
  end

  test "Breaking comes before Theme contract when a section has both" do
    changelog = "## 0.3.0 (2026-03-01)\n\n### Theme contract\n\n- C.\n\n### Added\n\n- A.\n\n### Breaking\n\n- B.\n"
    in_site("0.2.0") do |site|
      text = upgrade(site, changelog: changelog).run.text

      assert_operator text.index("### Breaking"), :<, text.index("### Theme contract")
      assert_operator text.index("### Theme contract"), :<, text.index("### Added")
    end
  end

  test "the migration warning appears only when an included section has Migrations needing action" do
    in_site("0.1.0") do |site|
      text = upgrade(site).run.text
      assert_includes text, "Going back to 0.1.0 after deploying is not safe"
      assert_includes text, "pg_dumpall"
    end

    in_site("0.2.0") do |site|
      text = upgrade(site).run.text
      assert_not_includes text, "not safe"
      assert_not_includes text, "pg_dumpall"
    end
  end

  test "no colour codes, whatever the terminal" do
    in_site("0.1.0") do |site|
      assert_not_includes upgrade(site).run.text, "\e["
    end
  end

  test "sections_between: pin equal to the version is empty, a pin older than all gets all, Unreleased never" do
    assert_empty ContentSpiel::Release.sections_between(CHANGELOG, "0.3.0", "0.3.0")
    assert_equal %w[0.1.0 0.2.0 0.3.0], ContentSpiel::Release.sections_between(CHANGELOG, "0.0.1", "0.3.0").map(&:first)
    assert_equal %w[0.2.0], ContentSpiel::Release.sections_between(CHANGELOG, "0.1.0", "0.2.0").map(&:first)
  end

  test "sections_between: headings without dates count, and a duplicate heading is one section" do
    changelog = "## 0.2.0\n\n- two\n\n## 0.10.0\n\n- ten\n\n## 0.2.0 (2026-02-01)\n\n- again\n"
    sections = ContentSpiel::Release.sections_between(changelog, "0.1.0", "0.10.0")

    assert_equal %w[0.2.0 0.10.0], sections.map(&:first)
    assert_equal "- two", sections.first.last
  end

  test "a version with no changelog section is said among the notes" do
    in_site("0.1.0") do |site|
      text = upgrade(site, changelog: "## 0.2.0 (2026-02-01)\n\n- two\n").run.text

      assert_includes text, "CHANGELOG has no section for 0.3.0."
      assert_includes text, "## 0.2.0"
    end
  end

  test "the pin keeps its file mode" do
    in_site("0.1.0") do |site|
      File.chmod(0o600, File.join(site, ".contentspiel-version"))
      upgrade(site).run

      assert_equal 0o600, File.stat(File.join(site, ".contentspiel-version")).mode & 0o7777
      assert_equal "0.3.0\n", pin(site)
    end
  end

  test "a rename that fails leaves the old pin and no temp file" do
    in_site("0.1.0") do |site|
      original = File.method(:rename)
      File.singleton_class.send(:define_method, :rename) { |*| raise Errno::EACCES, "rename" }
      begin
        assert_raises(Errno::EACCES) { upgrade(site).run }
      ensure
        File.singleton_class.send(:define_method, :rename, original)
      end

      assert_equal "0.1.0\n", pin(site)
      assert_empty Dir.children(site).grep(/tmp/)
    end
  end

  private

  def upgrade(site, changelog: CHANGELOG, check: NO_PROBLEMS)
    ContentSpiel::Upgrade.new(site, changelog: changelog, version: "0.3.0", check: check)
  end

  def pin(site) = File.read(File.join(site, ".contentspiel-version"))

  def in_site(pinned)
    Dir.mktmpdir do |dir|
      site = File.join(dir, "demo")
      FileUtils.mkdir_p File.join(site, "theme")
      File.write(File.join(site, ".contentspiel-version"), "#{pinned}\n")
      File.write(File.join(site, "config.yml"), "")
      FileUtils.mkdir_p File.join(site, "config")
      File.write(File.join(site, "config/deploy.yml"), "service: demo\n")
      yield site
    end
  end
end
