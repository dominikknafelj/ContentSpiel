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

      assert_equal "THEME_PATH names no directory: #{path}", error.message
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
end
