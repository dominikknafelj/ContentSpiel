require "test_helper"

# The theme folder as plain Ruby (theming spec §1 and §8): what THEME_PATH
# names, what is in it, and its fingerprint. The checks against the contract
# (a misspelt template, a shadowing asset) are Theme::Check's, because the
# contract is application code and this file is read before any is loaded.
class ThemeFolderTest < ActiveSupport::TestCase
  PLAIN = ThemeTestHelper::PLAIN

  def folder_with(files = {})
    Dir.mktmpdir("theme") do |dir|
      files.each do |relative, content|
        path = File.join(dir, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      yield dir
    end
  end

  # The boot's prepare raises on a refused folder and a reload's keeps the
  # refusal: which one is running is state of this class with no writer,
  # set by the hook `follow_boot` registered, so no other code can turn the
  # boot's refusal into a kept one.
  test "the boot is over once the application has started, and is followed once: a second follow_boot is refused" do
    assert ThemeFolder.booted?
    assert_not ThemeFolder.respond_to?(:booted=)
    error = assert_raises(ArgumentError) { ThemeFolder.follow_boot(Rails.application.config) }
    assert_includes error.message, "config/initializers/theme.rb"
    assert ThemeFolder.booted?
  end

  test "blank is the default theme" do
    [ nil, "", "   " ].each do |value|
      folder = ThemeFolder.from_env({ "THEME_PATH" => value })

      assert_not folder.configured?
      assert_nil folder.path
      assert_equal "default", folder.name
      assert_equal "default", folder.fingerprint
      assert_empty folder.files
      assert_empty folder.templates
      assert_empty folder.asset_paths
      assert_nil folder.stylesheet
      assert_nil folder.controllers_path
    end
  end

  test "the test environment ignores the variable" do
    assert_not ThemeFolder.from_env({ "THEME_PATH" => PLAIN.to_s, "RAILS_ENV" => "test" }).configured?
    assert ThemeFolder.from_env({ "THEME_PATH" => PLAIN.to_s, "RAILS_ENV" => "development" }).configured?
    assert_not ThemeFolder.current.configured?, "the suite itself runs under the default theme"
  end

  test "a relative path and a trailing slash name the same folder" do
    relative = ThemeFolder.from_env({ "THEME_PATH" => "test/fixtures/themes/plain/" }, base: Rails.root.to_s)

    assert_equal PLAIN, relative.path
    assert_equal "plain", relative.name
    assert_equal ThemeFolder.new(PLAIN).fingerprint, relative.fingerprint
  end

  test "a path that is a file or does not exist is refused, and the message names the variable and the path" do
    [ "/no/such/theme/anywhere", PLAIN.join("views/pages/show.html.erb").to_s ].each do |path|
      error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(path) }

      assert_equal "THEME_PATH names no directory: #{path}. Set THEME_PATH to the folder that holds the site's theme " \
                   "(its views, components, assets and javascript folders), or unset it to draw the site with the default theme.", error.message
    end
  end

  test "every refusal says what to do about it" do
    folder_with("lib/helper.rb" => "x") do |dir|
      assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, "Move it out of the folder or delete it."
    end
  end

  # A process that runs as root reads everything, so there is nothing to see.
  def unreadable(path)
    skip "root reads every file" if Process.uid.zero?
    mode = File.stat(path).mode
    File.chmod(0o000, path)
    yield
  ensure
    File.chmod(mode, path) if mode
  end

  test "a folder that cannot be read is a THEME_PATH problem, named with its path and what to do, at the top and below it" do
    folder_with("views/pages/show.html.erb" => "page") do |dir|
      [ dir, File.join(dir, "views"), File.join(dir, "views/pages") ].each do |locked|
        unreadable(locked) do
          error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }

          assert_includes error.message, "THEME_PATH: #{locked} cannot be read (Permission denied)"
          assert_includes error.message, "must be able to read every file and folder of the theme"
        end
      end
    end
  end

  test "a file that cannot be read is a THEME_PATH problem too, and never a bare system error" do
    folder_with("views/pages/show.html.erb" => "page") do |dir|
      file = File.join(dir, "views/pages/show.html.erb")
      folder = ThemeFolder.new(dir)
      unreadable(file) do
        [ -> { ThemeFolder.new(dir) }, -> { folder.fingerprint }, -> { folder.read("views/pages/show.html.erb") } ].each do |ask|
          error = assert_raises(ThemeFolder::Invalid, &ask)

          assert_includes error.message, "THEME_PATH: #{file} cannot be read (Permission denied)"
        end
      end
      assert_equal "page", folder.read("views/pages/show.html.erb")
    end
  end

  test "a link that leaves the folder stops it, a file's or a folder's, and the message names both ends" do
    Dir.mktmpdir("elsewhere") do |outside|
      File.write(File.join(outside, "show.html.erb"), "page")

      folder_with("views/pages/.keep" => "") do |dir|
        link = File.join(dir, "views/pages/show.html.erb")
        File.symlink(File.join(outside, "show.html.erb"), link)
        error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }

        assert_includes error.message, "THEME_PATH: #{link} is a link to " \
                                       "#{File.realpath(File.join(outside, "show.html.erb"))}, which is outside the theme folder"
        assert_includes error.message, "Copy what it links to into the theme in place of the link."
      end

      folder_with do |dir|
        File.symlink(outside, File.join(dir, "views"))

        assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, "is a link to #{File.realpath(outside)}, which is outside the theme folder"
      end
    end
  end

  test "a link to nothing and a link to a folder it is in stop it; a link that stays inside the folder is the file it names" do
    folder_with("views/pages/show.html.erb" => "page") do |dir|
      File.symlink(File.join(dir, "views/pages/show.html.erb"), File.join(dir, "views/pages/not_found.html.erb"))
      folder = ThemeFolder.new(dir)

      assert_equal %w[views/pages/not_found.html.erb views/pages/show.html.erb], folder.files
      assert_equal "page", folder.read("views/pages/not_found.html.erb")

      File.symlink(File.join(dir, "views/gone.html.erb"), File.join(dir, "views/pages/_lost.html.erb"))
      assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, "views/pages/_lost.html.erb is a link to nothing"
      File.delete(File.join(dir, "views/pages/_lost.html.erb"))

      File.symlink(File.join(dir, "views"), File.join(dir, "views/pages/again"))
      assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, "views/pages/again is a link to a folder it is in"
    end
  end

  test "a dot directory is not walked: what is in it is neither read nor followed" do
    Dir.mktmpdir("elsewhere") do |outside|
      folder_with("views/pages/show.html.erb" => "page", ".git/objects/pack" => "x") do |dir|
        File.symlink(outside, File.join(dir, ".git/hooks"))
        File.symlink(File.join(dir, "nothing"), File.join(dir, ".git/broken"))
        File.symlink(outside, File.join(dir, ".cache"))
        asked = []
        children = Dir.method(:children)

        with_singleton_override(Dir, :children, ->(directory) { asked << directory.to_s; children.call(directory) }) do
          assert_equal [ "views/pages/show.html.erb" ], ThemeFolder.new(dir).files
        end
        assert_not_empty asked
        assert_empty asked.grep(/\.git|\.cache/), "a dot directory was listed"
      end
    end
  end

  # At the top a dot directory is an editor's or a tool's (`.git`) and is
  # passed over. Below it, the folder is on a path Rails finds templates and
  # serves assets from: what is in `views/theme/.drafts/` would be neither
  # checked nor in the fingerprint, and still be there to be rendered.
  test "a dot directory below the top level is refused: it would be outside the check and the fingerprint, and still on the view path" do
    %w[views/theme/.drafts/_x.html.erb assets/images/.old/mark.svg components/.backup/blocks/image_component.html.erb].each do |file|
      folder_with("views/pages/show.html.erb" => "page", file => "x") do |dir|
        hidden = file[%r{\A.*?/\.[^/]+}]
        error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }

        assert_includes error.message, "THEME_PATH: #{File.join(dir, hidden)} is a hidden folder inside the theme"
        assert_includes error.message, "Move it out of the theme, or rename it without the dot."
      end
    end

    folder_with(".git/hooks/x" => "x", ".github/workflows/x.yml" => "x", "views/pages/.keep" => "", "views/.DS_Store" => "x",
      "views/pages/show.html.erb" => "page") do |dir|
      assert_equal [ "views/pages/show.html.erb" ], ThemeFolder.new(dir).files
    end
  end

  test "the fingerprint is read file by file and never as one string" do
    folder_with("assets/fonts/site.woff2" => "font" * 1000) do |dir|
      folder = ThemeFolder.new(dir)
      expected = Digest::SHA256.hexdigest("assets/fonts/site.woff2\0#{"font" * 1000}\0")

      whole = ->(*) { flunk "a file of the theme was read whole" }
      with_singleton_override(File, :binread, whole) do
        with_singleton_override(File, :read, whole) { assert_equal expected, folder.fingerprint }
      end
    end
  end

  test "an entry at the top that is not one of the four is refused by name" do
    folder_with("views/pages/show.html.erb" => "x", "lib/helper.rb" => "x") do |dir|
      error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }

      assert_includes error.message, "THEME_PATH"
      assert_includes error.message, File.join(dir, "lib")
      assert_includes error.message, "views, components, assets and javascript"
    end
    folder_with("notes.txt" => "x") do |dir|
      assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, File.join(dir, "notes.txt")
    end
    folder_with("views" => "a file, not a folder") do |dir|
      assert_includes assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }.message, File.join(dir, "views")
    end
  end

  # The real documentation theme had a `samples.md` at its top and eighteen
  # files with no place below it, and `theme:check` took two runs to say so.
  # Everything at the top that is no part of a theme is said in one refusal,
  # each with the sentence it had alone.
  test "every entry at the top that is no part of a theme is named in one refusal, a line each" do
    Dir.mktmpdir("theme") do |dir|
      FileUtils.mkdir_p(File.join(dir, "views"))
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "samples.md"), "x")
      File.write(File.join(dir, "assets"), "a file named like a folder")

      error = assert_raises(ThemeFolder::Invalid) { ThemeFolder.new(dir) }
      lines = error.message.lines(chomp: true)

      assert_equal 3, lines.size, error.message
      assert_equal %w[assets lib samples.md], lines.map { |line| line[%r{/([^/ ]+) is not part of a theme}, 1] }
      lines.each do |line|
        assert line.start_with?("THEME_PATH: #{File.realpath(dir)}/") || line.start_with?("THEME_PATH: #{dir}/"), line
        assert line.end_with?("Move it out of the folder or delete it."), line
      end
    end
  end

  test "dot files anywhere and a README at the top are not the theme's files" do
    folder_with("README.md" => "about", ".DS_Store" => "x", ".git/config" => "x", "views/.DS_Store" => "x",
      "views/pages/.keep" => "", "views/pages/show.html.erb" => "page") do |dir|
      folder = ThemeFolder.new(dir)

      assert_equal [ "views/pages/show.html.erb" ], folder.files
      assert_equal ThemeFolder.new(dir).fingerprint, folder.fingerprint

      File.write(File.join(dir, "views/.DS_Store"), "changed")
      File.write(File.join(dir, "README.md"), "changed")
      assert_equal folder.fingerprint, ThemeFolder.new(dir).fingerprint, "an ignored file is not in the fingerprint"
    end
  end

  test "a README below the top is a file like any other" do
    folder_with("views/README.md" => "x") do |dir|
      assert_equal [ "views/README.md" ], ThemeFolder.new(dir).files
    end
  end

  test "an empty folder is a theme with no templates" do
    folder_with do |dir|
      folder = ThemeFolder.new(dir)

      assert folder.configured?
      assert_empty folder.files
      assert_empty folder.templates
      assert_match(/\A\h{64}\z/, folder.fingerprint)
      assert_not_equal "default", folder.fingerprint
    end
  end

  test "the boot line of a folder that holds nothing of a theme says that it replaces nothing" do
    folder_with("README.md" => "about", ".keep" => "") do |dir|
      folder = ThemeFolder.new(dir)

      assert_equal "[ContentSpiel] Theme: #{folder.path} holds no file of a theme and replaces nothing: the default theme draws " \
                   "the site (fingerprint #{folder.fingerprint[0, 8]})", ThemeFolder.announcement(folder)
    end
  end

  test "the second theme's files, templates, stylesheet, controllers and asset folders" do
    folder = ThemeFolder.new(PLAIN)

    assert_includes folder.files, "components/blocks/rich_text_component.html.erb"
    assert_includes folder.files, "assets/images/plain-mark.svg"
    assert_equal folder.files.sort, folder.files
    assert_equal folder.files.grep(/\.erb\z/), folder.templates
    assert_includes folder.asset_paths, PLAIN.join("assets/images")
    assert_not_includes folder.asset_paths, PLAIN.join("assets/fonts"), "a folder the theme does not have is not a path"
  end

  test "the fingerprint is the same for the same files, and another for one changed byte, a renamed file or an added one" do
    folder_with("views/pages/show.html.erb" => "page", "assets/stylesheets/theme.css" => "a{}") do |dir|
      first = ThemeFolder.new(dir).fingerprint
      assert_equal first, ThemeFolder.new(dir).fingerprint

      File.write(File.join(dir, "assets/stylesheets/theme.css"), "a{ }")
      second = ThemeFolder.new(dir).fingerprint
      assert_not_equal first, second

      File.rename(File.join(dir, "views/pages/show.html.erb"), File.join(dir, "views/pages/not_found.html.erb"))
      third = ThemeFolder.new(dir).fingerprint
      assert_not_equal second, third

      File.write(File.join(dir, "views/pages/show.html.erb"), "")
      assert_not_equal third, ThemeFolder.new(dir).fingerprint
    end
  end

  test "two folders with the same files have the same fingerprint, wherever they are" do
    folder_with("views/pages/show.html.erb" => "page") do |one|
      folder_with("views/pages/show.html.erb" => "page") do |two|
        assert_equal ThemeFolder.new(one).fingerprint, ThemeFolder.new(two).fingerprint
      end
    end
  end

  test "moving bytes from one file's end to the next file's name does not keep the fingerprint" do
    folder_with("views/a" => "bc") do |one|
      folder_with("views/ab" => "c") do |two|
        assert_not_equal ThemeFolder.new(one).fingerprint, ThemeFolder.new(two).fingerprint
      end
    end
  end

  test "the boot line names the folder, its templates and the start of its fingerprint, or says there is none" do
    folder = ThemeFolder.new(PLAIN)

    assert_equal "[ContentSpiel] Theme: #{PLAIN} (#{folder.templates.size} templates, fingerprint #{folder.fingerprint[0, 8]})",
      ThemeFolder.announcement(folder)
    assert_equal "[ContentSpiel] Theme: the default theme (THEME_PATH is not set)", ThemeFolder.announcement(ThemeFolder.new(nil))
  end

  test "a theme's controllers are pinned under controllers/theme, served from controllers, and preloaded for the site entry point alone" do
    pins = ThemeFolder.new(PLAIN).pins

    assert_equal({ dir: PLAIN.join("javascript/controllers").to_s, under: "controllers/theme", to: "controllers", preload: "site" }, pins)
    assert_nil ThemeFolder.new(nil).pins

    map = Importmap::Map.new
    map.pin_all_from(pins[:dir], under: pins[:under], to: pins[:to], preload: pins[:preload])
    resolver = Object.new
    def resolver.path_to_asset(path) = "/assets/#{path}"

    assert_equal({ "controllers/theme/hello_controller" => "/assets/controllers/hello_controller.js" }, JSON.parse(map.to_json(resolver: resolver))["imports"])
  end

  test "the test environment's import map holds the second theme's controller, and its script is on the asset path" do
    imports = JSON.parse(Rails.application.importmap.to_json(resolver: ActionController::Base.helpers, cache_key: :theme_folder_test))["imports"]

    assert_match %r{/assets/controllers/hello_controller-\h+\.js\z}, imports.fetch("controllers/theme/hello_controller")
    assert Rails.application.assets.load_path.find("plain-mark.svg")
  end

  # `bin/rails theme:check` starts the application inside this block, and
  # the initializer then keeps a refusal of the folder where a boot raises
  # it (config/initializers/theme.rb; the whole of it is tried in a process
  # of its own in test/tasks/theme_tasks_test.rb).
  test "checking is so for the length of its block and no longer, also when the block raises" do
    assert_not ThemeFolder.checking?
    assert_equal :done, ThemeFolder.checking { ThemeFolder.checking? ? :done : :not }
    assert_not ThemeFolder.checking?

    assert_raises(ThemeFolder::Invalid) { ThemeFolder.checking { raise ThemeFolder::Invalid, "x" } }
    assert_not ThemeFolder.checking?
  end
end
