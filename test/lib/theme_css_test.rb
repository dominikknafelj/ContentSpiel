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

  # The scripts too: a utility a controller adds (`classList.add("hidden")`)
  # and no template writes would otherwise be built for nobody, in silence.
  test "with a theme the entry imports the default first, then the theme's stylesheet, and scans the theme's templates and scripts" do
    assert_equal <<~CSS, ThemeCss.entry(ThemeFolder.new(PLAIN), root: ROOT)
      @import "../../app/assets/tailwind/themes/default/theme.css";
      @import "../../test/fixtures/themes/plain/assets/stylesheets/theme.css";
      @source "../../app/assets/tailwind/themes/default";
      @source "../../test/fixtures/themes/plain/assets/stylesheets";
      @source "../../test/fixtures/themes/plain/views";
      @source "../../test/fixtures/themes/plain/components";
      @source "../../test/fixtures/themes/plain/javascript";
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

  # No stamp is no build (a build that failed takes it away, an image whose
  # last stage left app/assets/builds behind has none): nothing "was built
  # for another theme" then.
  test "with no stamp the refusal says the stylesheet was not built, for a theme and for none, and how to build" do
    Dir.mktmpdir("root") do |root|
      themed = ThemeFolder.not_built_message(ThemeFolder.new(PLAIN), root)
      assert_equal "THEME_PATH: the public stylesheet was not built, or its build failed: there is no stamp of a build " \
        "(app/assets/builds/.theme.stamp). Run assets:precompile with THEME_PATH set " \
        "(SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile) when the image is built, and keep app/assets/builds in the image.", themed

      default = ThemeFolder.not_built_message(ThemeFolder.new(nil), root)
      assert_includes default, "Run assets:precompile without THEME_PATH"
      assert_no_match(/another theme/, themed + default)
    end
  end

  # The stamp is never served: it is a dot file, which Propshaft leaves out
  # of its load path (`Propshaft::LoadPath#without_dotfiles`), so it is no
  # asset, is not copied to public/assets and is not in the manifest, and
  # System status' eight characters are all anyone is shown of it.
  test "the stamp is a dot file beside the stylesheet, and no asset: not found, not listed, not served" do
    assert_equal "app/assets/builds/.theme.stamp", ThemeFolder::STAMP
    assert Rails.root.join(ThemeFolder::STAMP).file?, "bin/rails tailwindcss:build stamps the stylesheet the tests read"

    load_path = Rails.application.assets.load_path
    assert load_path.find("theme.css"), "the stylesheet beside it is an asset"
    assert_empty load_path.assets.map { |asset| asset.logical_path.to_s }.grep(/stamp/)
    assert_empty load_path.manifest.to_json.scan(/[^"]*stamp[^"]*/)
    assert_not Rails.root.join("app/assets/builds/theme.stamp").exist?, "a stamp under the old name would be served"
  end

  # `ThemeCss.build` is the build both tasks run (lib/tasks/theme_css.rake):
  # the stamp is written AFTER the executable succeeded and taken away
  # before it starts, so a stamp never vouches for a build that failed.
  test "a build stamps after the executable succeeded; a failed one leaves no stamp, an earlier one's included" do
    Dir.mktmpdir("root") do |root|
      plain = ThemeFolder.new(PLAIN)

      ThemeCss.build(plain, root: root, executable: "true")
      assert_equal plain.fingerprint, ThemeFolder.stamp(root)
      assert_equal ThemeCss.entry(plain, root: root), Pathname(root).join(ThemeCss::ENTRY).read

      assert_raises(RuntimeError) { ThemeCss.build(plain, root: root, executable: "false") }
      assert_nil ThemeFolder.stamp(root)
    end
  end

  test "the stamp is the fingerprint read before the build: a file changed while it ran is not vouched for" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        before = folder.fingerprint
        script = File.join(root, "tailwind")
        File.write(script, "#!/bin/sh\necho changed >> #{dir.join("assets/stylesheets/theme.css")}\n")
        File.chmod(0o755, script)

        ThemeCss.build(folder, root: root, executable: script)

        assert_equal before, ThemeFolder.stamp(root)
        assert_not folder.built?(root)
      end
    end
  end

  # The watch's half (lib/tasks/theme_css.rake). Tailwind's watcher builds
  # on a change by itself, but nobody hears whether it succeeded, so the
  # keeper builds once itself (`build`) and stamps what it built.
  test "while it is kept stamped, a changed theme is built and stamped with its new fingerprint; the default theme needs no keeping" do
    Dir.mktmpdir("root") do |root|
      assert_nil ThemeCss.keep_stamped(ThemeFolder.new(nil), root: root, build: -> { flunk "nothing to build" })

      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        before = folder.fingerprint
        builds = 0

        keeping(folder, root: root, build: -> { builds += 1 }) do |keeper|
          let_it_ask(keeper)
          assert_equal 0, builds, "nothing changed, nothing is built"

          dir.join("assets/stylesheets/theme.css").write(".changed { color: red; }\n")
          assert_not_equal before, folder.fingerprint
          await { folder.built?(root) }

          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
          assert_equal 1, builds

          # A stamp another build wrote since is that build's, and stays.
          ThemeCss.stamp!(ThemeFolder.new(nil), root: root)
          let_it_ask(keeper)
          dir.join("assets/stylesheets/theme.css").write(".changed { color: blue; }\n")
          let_it_ask(keeper)
          assert_equal "default", ThemeFolder.stamp(root)
          assert_equal 1, builds

          # Until somebody builds for the theme again (bin/rails
          # tailwindcss:build with THEME_PATH set): that stamp is the
          # folder's, the keeper takes it for its own and goes on keeping.
          ThemeCss.stamp!(folder, root: root)
          let_it_ask(keeper)
          dir.join("assets/stylesheets/theme.css").write(".changed { color: green; }\n")
          await { folder.built?(root) }
          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
          assert_equal 2, builds
          assert keeper.alive?
        end
      end
    end
  end

  test "a build that fails while the theme is kept takes the stamp away, and the next change that builds puts it back" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        succeeds = false

        keeping(folder, root: root, build: -> { succeeds }) do
          dir.join("assets/stylesheets/theme.css").write(".broken {\n")
          await { ThemeFolder.stamp(root).nil? }
          assert_nil ThemeFolder.stamp(root)

          succeeds = true
          dir.join("assets/stylesheets/theme.css").write(".mended { color: red; }\n")
          await { folder.built?(root) }
          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
        end
      end
    end
  end

  # A theme that gains its stylesheet or its components folder while the
  # watch runs is in no line of the entry the watch started with.
  test "a theme that gains a folder while it is kept gets its entry written again before the build" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        FileUtils.rm_r(dir.join("components"))
        folder = ThemeFolder.new(dir)
        ThemeCss.write_entry(folder, root: root)
        ThemeCss.stamp!(folder, root: root)
        entry = Pathname(root).join(ThemeCss::ENTRY)
        assert_no_match(/components/, entry.read)
        at_build = nil

        keeping(folder, root: root, build: -> { at_build = entry.read }) do
          dir.join("components/blocks").mkpath
          dir.join("components/blocks/rich_text_component.html.erb").write("<div></div>\n")
          await { folder.built?(root) }

          assert_match(/@source ".*\/components";/, at_build)
        end
      end
    end
  end

  # The folder is hashed only when a glance at it (names, sizes, times) says
  # something changed: a theme with large images costs a listing a second.
  test "a kept theme is listed every turn and hashed only when the listing changed" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        hashed = 0
        glanced = 0
        real_fingerprint = folder.method(:fingerprint)
        real_glance = folder.method(:glance)
        folder.define_singleton_method(:fingerprint) { hashed += 1; real_fingerprint.call }
        folder.define_singleton_method(:glance) { glanced += 1; real_glance.call }

        keeping(folder, root: root, build: -> { true }) do |keeper|
          let_it_ask(keeper)
          assert_operator glanced, :>, 3
          assert_equal 0, hashed

          # Put in place in ONE step (written beside, then renamed): a plain
          # write empties the file first, and a keeper that glances between
          # the two sees two changes and hashes twice, rightly (seen once in
          # sixteen runs).
          Pathname(root).join("mark.svg").write("<svg xmlns=\"http://www.w3.org/2000/svg\"/>\n")
          File.rename(Pathname(root).join("mark.svg"), dir.join("assets/images/plain-mark.svg"))
          await { ThemeFolder.stamp(root) == real_fingerprint.call }
          let_it_ask(keeper)
          assert_equal 1, hashed
        end
      end
    end
  end

  # The stamp written is the fingerprint the keeper READ, not one read a
  # second time: the folder can change between the two (a checkout, a
  # "save all"), and a keeper that remembered one value and wrote another
  # took its own stamp for somebody else's from then on and never wrote
  # again.
  test "the keeper stamps the fingerprint it read, and so still knows its own stamp at the next change" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        answers = %w[first second third fourth]
        asked = 0
        folder.define_singleton_method(:fingerprint) { answers.fetch(asked).tap { asked += 1 } }

        keeping(folder, root: root, build: -> { true }) do
          dir.join("assets/stylesheets/theme.css").write(".one { color: red; }\n")
          await { asked >= 1 && !ThemeFolder.stamp(root).match?(/\A\h{64}\z/) }
          assert_equal "first", ThemeFolder.stamp(root), "the value read, not a second reading"
          assert_equal 1, asked

          dir.join("assets/stylesheets/theme.css").write(".two { color: blue; } /* longer */\n")
          await { ThemeFolder.stamp(root) == "second" }
          assert_equal "second", ThemeFolder.stamp(root), "the keeper still takes the stamp for its own"
        end
      end
    end
  end

  test "an error of any kind in a turn is said once, without a path, and the keeper goes on" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        folder = ThemeFolder.new(dir)
        ThemeCss.stamp!(folder, root: root)
        said = []
        raises = true
        build = -> { raises ? raise(IOError, "closed stream #{dir}") : true }

        keeping(folder, root: root, build: build, log: ->(line) { said << line }) do |keeper|
          dir.join("assets/stylesheets/theme.css").write(".one { color: red; }\n")
          await { said.any? }
          let_it_ask(keeper)
          assert keeper.alive?
          assert_equal [ "theme_css:watch: the stylesheet's stamp could not be kept (IOError); it will be tried again" ], said

          raises = false
          dir.join("assets/stylesheets/theme.css").write(".two { color: blue; } /* longer */\n")
          await { folder.built?(root) }
          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
          assert_equal 1, said.size
        end
      end
    end
  end

  # R2 of the re-review. `theme_css:watch` is one of the three processes of
  # bin/dev, and Foreman stops them all when one ends. Its first build
  # raised when the stylesheet did not build (a half-written `@import`), so
  # a person whose theme had a CSS error could not start the server at all.
  # And Tailwind's own watcher is no help there: started on an entry that
  # does not build, it prints the error and EXITS (seen with 4.3.3; one
  # that is running when the stylesheet breaks stays). So the watch says
  # that the build failed and waits for a file to change.
  #
  # The stand-in for the executable fails while the theme's stylesheet holds
  # the word "broken", and as the watcher (`-w`) notes that it was started
  # and ends well at once.
  test "the watch goes on when the stylesheet does not build: it says so, and builds, stamps and watches once the file is mended" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        stylesheet = dir.join("assets/stylesheets/theme.css")
        stylesheet.write("broken\n")
        script = File.join(root, "tailwind")
        File.write(script, <<~SH)
          #!/bin/sh
          if grep -q broken "#{stylesheet}"; then exit 1; fi
          for last; do :; done
          if [ "$last" = "-w" ]; then echo watching >> "#{root}/calls"; else echo built >> "#{root}/calls"; fi
        SH
        File.chmod(0o755, script)
        folder = ThemeFolder.new(dir)
        said = []
        calls = -> { File.exist?("#{root}/calls") ? File.readlines("#{root}/calls", chomp: true) : [] }

        before = Thread.list.select(&:alive?)
        watch = Thread.new { ThemeCss.watch(folder, root: root, executable: script, every: 0.01, log: ->(line) { said << line }) }
        begin
          await { said.any? }
          assert_equal [ "theme_css:watch: the public stylesheet did not build; what Tailwind said of it is above. The watch goes on, " \
                         "and builds again when a file of the theme or of the default theme's styles changes." ], said
          assert watch.alive?, "the watch did not end with the failed build"
          assert_nil ThemeFolder.stamp(root), "a build that failed vouches for nothing"
          assert_empty calls.call

          stylesheet.write(".mended { color: red; }\n")
          await { !watch.alive? }

          assert_includes calls.call, "built"
          assert_includes calls.call, "watching", "the watcher is started once the stylesheet builds"
          await { (Thread.list.select(&:alive?) - before).empty? }
          assert_empty Thread.list.select(&:alive?) - before, "the stamp's keeper ends with the watch"
          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
          assert_equal 1, said.size, "said once for one failure"
        ensure
          watch.kill
          watch.join
        end
      end
    end
  end

  # The wait between two tries compared one look at the folder with the
  # next, and a folder that cannot be listed gave a look that is never the
  # last one's (it held the time). So with the stylesheet broken AND the
  # folder gone (renamed, deleted, a file made unreadable) the loop never
  # slept: thousands of rounds and lines a second under bin/dev.
  test "while the theme folder cannot be listed the watch waits a turn at a time and says so once, and goes on when the folder is back" do
    Dir.mktmpdir("root") do |root|
      with_theme_copy do |dir|
        stylesheet = dir.join("assets/stylesheets/theme.css")
        stylesheet.write("broken\n")
        script = File.join(root, "tailwind")
        File.write(script, <<~SH)
          #!/bin/sh
          echo run >> "#{root}/runs"
          if grep -q broken "#{stylesheet}"; then exit 1; fi
        SH
        File.chmod(0o755, script)
        folder = ThemeFolder.new(dir)
        away = "#{dir}-away"
        said = []
        runs = -> { File.exist?("#{root}/runs") ? File.readlines("#{root}/runs").size : 0 }

        watch = Thread.new { ThemeCss.watch(folder, root: root, executable: script, every: 0.05, log: ->(line) { said << line }) }
        begin
          await { said.any? }
          File.rename(dir.to_s, away)
          sleep 0.6 # twelve turns of the watch with the folder gone

          assert watch.alive?
          assert_equal [ "did not build", "cannot be read" ], said.map { |line| line[/did not build|cannot be read/] }, said.inspect
          assert_includes said.last, "theme_css:watch: the theme folder cannot be read (Errno::ENOENT). The watch goes on, and looks again"
          assert_operator runs.call, :<=, 2, "the executable is not started for a folder that is not there"

          File.rename(away, dir.to_s)
          stylesheet.write(".mended { color: red; }\n")
          await { !watch.alive? }

          assert_equal folder.fingerprint, ThemeFolder.stamp(root)
          assert_equal 2, said.size, said.inspect
        ensure
          File.rename(away, dir.to_s) if File.directory?(away)
          watch.kill
          watch.join
        end
      end
    end
  end

  private
    def keeping(folder, root:, build:, **options)
      keeper = ThemeCss.keep_stamped(folder, root: root, build: build, every: 0.01, **options)
      yield keeper
    ensure
      keeper&.kill
      keeper&.join
    end

    def await
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

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
