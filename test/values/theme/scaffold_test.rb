require "test_helper"

# `bin/rails 'theme:new[PATH]'` (theming spec, decision 15): the default
# theme written into a folder of a theme's shape. What it writes IS the
# contract's lists, so a template added to the contract is copied the day it
# is added, and a theme made this way draws the site exactly as before.
class Theme::ScaffoldTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    SiteSetting.instance.update!(title: "Dana's Notes")
    @home = root_page
    blog = create_page(title: "Blog")
    [ [ @home, "rich_text", {}, { "en" => { body: rich_doc("## Welcome\n\nWords of the homepage") } } ],
      [ blog, "post_list", { settings: { "content_type" => "blog" } }, {} ] ].each do |page, type, attributes, translations|
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: type }.merge(attributes), translations: translations)
      assert result.ok?, result.errors.to_sentence
      publish_changes(page)
    end
    create_post(title: "First post")
  end

  def scaffolded
    Dir.mktmpdir("theme") do |dir|
      target = File.join(dir, "site-theme")
      yield Pathname(target), Theme::Scaffold.write(target)
    end
  end

  def body_of(path)
    get path
    response.body.gsub(/ nonce="[^"]*"/, "")
  end

  test "it writes every template and component of the contract, a stylesheet, and the folders a theme may fill" do
    scaffolded do |target, written|
      Theme::Contract::TEMPLATES.each_key do |path|
        assert_equal Rails.root.join("app/views", path).read, target.join("views", path).read, path
      end
      Theme::Contract::COMPONENTS.each_key do |path|
        assert_equal Rails.root.join("app/components/#{path}.html.erb").read, target.join("components/#{path}.html.erb").read, path
      end
      assert target.join("assets/stylesheets/theme.css").file?
      %w[assets/images assets/fonts javascript/controllers views/theme].each { |folder| assert target.join(folder).directory?, folder }
      assert target.join("README.md").file?

      assert_equal ThemeFolder.new(target).files.sort, (written - [ "README.md" ]).sort, "it says what it wrote, and wrote nothing the folder does not count"
      assert_equal Theme::Contract::TEMPLATES.size + Theme::Contract::COMPONENTS.size + 1, ThemeFolder.new(target).files.size
    end
  end

  test "the folder it writes has no problem, checked deeply, and loads" do
    scaffolded do |target, _written|
      assert_empty Theme::Check.problems(ThemeFolder.new(target), deep: true)
      assert_equal Theme::Contract::TEMPLATES.size + Theme::Contract::COMPONENTS.size, Theme.load(ThemeFolder.new(target)).template_count
    end
  end

  test "its stylesheet declares nothing and names every token of the contract" do
    scaffolded do |target, _written|
      css = target.join("assets/stylesheets/theme.css").read

      assert_empty css.gsub(%r{/\*.*?\*/}m, "").strip, "the stylesheet is a comment and nothing else: the site looks as before"
      Theme::Contract::TOKENS.each { |token| assert_includes css, token }
    end
  end

  test "a site under the folder it writes is drawn byte for byte as under the default theme" do
    paths = [ "/", "/blog", "/blog/first-post", "/de/", "/no-such-page" ]
    default = paths.index_with { |path| body_of(path) }

    scaffolded do |target, _written|
      Theme.with(Theme.load(ThemeFolder.new(target))) do
        paths.each { |path| assert_equal default.fetch(path), body_of(path), "#{path} differs under the copied theme" }
      end
    end
  end

  # An integrator makes the repository first: `mkdir theme && cd theme &&
  # git init`, perhaps a README and a .gitignore. None of that is a theme's
  # file (`ThemeFolder` passes each over), so the folder is still empty for
  # this command, which leaves all of it as it is.
  test "a folder that holds only a repository, dot files and a README is empty: it is written into, and the README is kept" do
    Dir.mktmpdir("theme") do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git/objects"))
      File.write(File.join(dir, ".git/HEAD"), "ref: refs/heads/main\n")
      File.write(File.join(dir, ".gitignore"), "node_modules\n")
      File.write(File.join(dir, ".DS_Store"), "x")
      File.write(File.join(dir, "README.md"), "# Our site's theme\n")

      written = Theme::Scaffold.write(dir)

      assert_not_includes written, "README.md"
      assert_equal "# Our site's theme\n", File.read(File.join(dir, "README.md"))
      assert_equal "ref: refs/heads/main\n", File.read(File.join(dir, ".git/HEAD"))
      assert_equal ThemeFolder.new(dir).files.sort, written.sort
      assert_empty Theme::Check.problems(ThemeFolder.new(dir), deep: true)

      File.write(File.join(dir, "notes.txt"), "x")
      FileUtils.rm_rf(File.join(dir, "views"))
      assert_raises(Theme::Scaffold::Refused) { Theme::Scaffold.write(dir) }
    end
  end

  # Equal bodies are also what a copy that is never looked at gives. So in a
  # copy of its own (templates are cached by their path in this environment)
  # one template and one component are changed, and the change is drawn:
  # the site is drawn BY the copy.
  test "a template and a component changed in the folder it writes are what the site is drawn with" do
    scaffolded do |target, _written|
      page = target.join("views/pages/show.html.erb")
      page.write("<p id=\"copied-page\">drawn by the copy</p>\n#{page.read}")
      target.join("components/blocks/rich_text_component.html.erb").write("<p id=\"copied-block\">drawn by the copy</p>\n")

      Theme.with(Theme.load(ThemeFolder.new(target))) do
        assert_includes body_of("/"), %(<p id="copied-page">drawn by the copy</p>)
        assert_includes body_of("/"), %(<p id="copied-block">drawn by the copy</p>)
      end
      assert_not_includes body_of("/"), "drawn by the copy"
    end
  end

  test "it writes into an empty folder, and refuses one that holds anything or a path that is a file" do
    Dir.mktmpdir("theme") do |dir|
      assert_operator Theme::Scaffold.write(dir).size, :>, 10

      error = assert_raises(Theme::Scaffold::Refused) { Theme::Scaffold.write(dir) }
      assert_includes error.message, dir
      assert_includes error.message, "is not empty"

      file = File.join(dir, "README.md")
      assert_raises(Theme::Scaffold::Refused) { Theme::Scaffold.write(file) }
    end
  end
end
