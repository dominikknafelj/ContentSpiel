require "test_helper"

# The public stylesheet's entry file (theming spec §4): the default theme's
# styles, then the theme's stylesheet, then where the theme's templates are
# for the utility scan. Text only: the build itself is tried once in CI
# (`bin/theme-build-check`), because it writes app/assets/builds, which
# every other test reads.
class ThemeCssTest < ActiveSupport::TestCase
  PLAIN = ThemeTestHelper::PLAIN
  ROOT = Rails.root

  test "without a theme the entry is the default theme's file, and its folder for the watch, and nothing else" do
    assert_equal <<~CSS, ThemeCss.entry(ThemeFolder.new(nil), root: ROOT)
      @import "../../app/assets/tailwind/themes/default/theme.css";
      @source "../../app/assets/tailwind/themes/default";
    CSS
  end

  test "with a theme the entry imports the default first, then the theme's stylesheet, and scans the theme's templates" do
    assert_equal <<~CSS, ThemeCss.entry(ThemeFolder.new(PLAIN), root: ROOT)
      @import "../../app/assets/tailwind/themes/default/theme.css";
      @import "../../test/fixtures/themes/plain/assets/stylesheets/theme.css";
      @source "../../app/assets/tailwind/themes/default";
      @source "../../test/fixtures/themes/plain/assets/stylesheets";
      @source "../../test/fixtures/themes/plain/views";
      @source "../../test/fixtures/themes/plain/components";
    CSS
  end

  test "a theme outside the application is named by a relative path that leads back to it" do
    with_theme_copy do |dir|
      entry = ThemeCss.entry(ThemeFolder.new(dir), root: ROOT)
      paths = entry.scan(/"([^"]+)"/).flatten

      assert paths.all? { |path| path.start_with?("../") }, "every path is relative to the entry file: #{paths.inspect}"
      resolved = paths.map { |path| ROOT.join("tmp/theme", path).cleanpath }
      assert_includes resolved, dir.realpath.join("assets/stylesheets/theme.css")
      assert_includes resolved, dir.realpath.join("views")
      assert_includes resolved, dir.realpath.join("components")
    end
  end

  # Tailwind's watcher reports a changed file by its real path and compares
  # it with the path the entry names, so the entry names the real one.
  test "a theme reached through a link is named by where it really is" do
    with_theme_copy do |dir|
      Dir.mktmpdir("link") do |elsewhere|
        link = File.join(elsewhere, "theme")
        File.symlink(dir, link)
        entry = ThemeCss.entry(ThemeFolder.new(link), root: ROOT)
        resolved = entry.scan(/"([^"]+)"/).flatten.map { |path| ROOT.join("tmp/theme", path).cleanpath.to_s }

        assert_includes resolved, dir.realpath.join("views").to_s
        assert_empty resolved.grep(/#{Regexp.escape(File.basename(elsewhere))}/), "no line names the link"
      end
    end
  end

  # Tailwind's watcher watches the entry's own folder and the folders its
  # `@source` lines name, and not the folder of a file the entry imports: so
  # every folder a stylesheet is imported from is a `@source` line too, or
  # `theme_css:watch` builds a changed tokens.css or theme.css never.
  test "every folder a stylesheet is imported from is watched: it is a source too" do
    [ ThemeFolder.new(nil), ThemeFolder.new(PLAIN) ].each do |folder|
      entry = ThemeCss.entry(folder, root: ROOT)
      imported = entry.scan(/@import "([^"]+)"/).flatten.map { |path| File.dirname(path) }
      sources = entry.scan(/@source "([^"]+)"/).flatten

      assert_not_empty imported
      assert_empty imported - sources, "imported from a folder the watch does not watch: #{(imported - sources).inspect}"
    end
  end

  test "a theme with no stylesheet and no components brings only what it has" do
    Dir.mktmpdir("theme") do |dir|
      FileUtils.mkdir_p(File.join(dir, "views/theme"))
      entry = ThemeCss.entry(ThemeFolder.new(dir), root: ROOT)

      assert_equal 3, entry.lines.size
      assert_match(/\A@import ".*themes\/default\/theme\.css";\n@source ".*themes\/default";\n@source ".*\/views";\n\z/, entry)
    end
  end

  test "the entry is written under tmp/theme, and the command builds theme.css from it" do
    Dir.mktmpdir("root") do |root|
      path = ThemeCss.write_entry(ThemeFolder.new(nil), root: root)

      assert_equal Pathname(root).join("tmp/theme/entry.css"), path
      assert_equal ThemeCss.entry(ThemeFolder.new(nil), root: root), path.read
      assert_equal [ "tailwindcss", "-i", File.join(root, "tmp/theme/entry.css"), "-o", File.join(root, "app/assets/builds/theme.css"), "--minify" ],
        ThemeCss.command(root: root, executable: "tailwindcss")
    end
  end

  test "the build's stamp is the theme's fingerprint, and a folder is built when the stamp is its own" do
    Dir.mktmpdir("root") do |root|
      plain = ThemeFolder.new(PLAIN)
      default = ThemeFolder.new(nil)

      assert_nil ThemeFolder.stamp(root)
      assert_not plain.built?(root)
      assert_not default.built?(root), "no stamp is no build, for the default theme too"

      ThemeCss.stamp!(plain, root: root)
      assert_equal plain.fingerprint, ThemeFolder.stamp(root)
      assert plain.built?(root)
      assert_not default.built?(root)

      ThemeCss.stamp!(default, root: root)
      assert_equal "default", ThemeFolder.stamp(root)
      assert default.built?(root)
      assert_not plain.built?(root)
    end
  end

  test "the refusal says which way round it is and how to build" do
    Dir.mktmpdir("root") do |root|
      ThemeCss.stamp!(ThemeFolder.new(nil), root: root)

      themed = ThemeFolder.not_built_message(ThemeFolder.new(PLAIN), root)
      assert_includes themed, "the stylesheet was built for another theme: run assets:precompile with THEME_PATH set"
      assert_includes themed, "SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile"

      ThemeCss.stamp!(ThemeFolder.new(PLAIN), root: root)
      assert_includes ThemeFolder.not_built_message(ThemeFolder.new(nil), root),
        "the stylesheet was built for another theme: run assets:precompile without THEME_PATH"
    end
  end

  # The watch's half (lib/tasks/theme_css.rake): Tailwind rebuilds on a
  # change, and the stamp follows the folder, so System status does not say
  # "built for another theme" about a stylesheet the watch has just built.
  test "while it is kept stamped, a changed theme's stamp becomes its new fingerprint; the default theme needs no keeping" do
    Dir.mktmpdir("root") do |root|
      assert_nil ThemeCss.keep_stamped(ThemeFolder.new(nil), root: root)

      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        before = folder.fingerprint
        keeper = ThemeCss.keep_stamped(folder, root: root, every: 0.01)

        begin
          dir.join("assets/stylesheets/theme.css").write(".changed { color: red; }\n")
          assert_not_equal before, folder.fingerprint
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
          Thread.pass until folder.built?(root) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          assert_equal folder.fingerprint, ThemeFolder.stamp(root)

          # A stamp another build wrote since is that build's, and stays.
          ThemeCss.stamp!(ThemeFolder.new(nil), root: root)
          changed = folder.fingerprint
          dir.join("assets/stylesheets/theme.css").write(".changed { color: blue; }\n")
          assert_not_equal changed, folder.fingerprint
          let_it_ask(keeper)
          assert_equal "default", ThemeFolder.stamp(root)
          assert keeper.alive?
        ensure
          keeper.kill
          keeper.join
        end
      end
    end
  end

  private
    # Long enough for a keeper that asks every hundredth of a second to have
    # asked several times.
    def let_it_ask(keeper)
      turns = 0
      while keeper.alive? && turns < 30
        sleep 0.01
        turns += 1
      end
    end
end
