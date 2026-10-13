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
    wide_page
  end

  # A page that every component of the contract draws: the scaffold copies
  # eight, and a comparison on a text and one blog list would not notice the
  # day the copy of the image block, the section or the other two lists is
  # not what the default theme draws. An image, a section of three columns
  # (tinted, full width) holding a text, an image and a blog list, a resume
  # list, a "now" list, an image block with no image, a struck text; and a
  # post of each type, whose own page is the detail component.
  def wide_page
    wide = create_page(title: "Wide", translations: { "es" => { title: "Ancho", slug: "ancho" } })
    asset = create_media_asset
    add = lambda do |type, attributes = {}, translations = {}|
      result = ContentBlocks::Save.call(ContentBlock.new(owner: wide), attributes: { block_type: type }.merge(attributes), translations: translations)
      assert result.ok?, result.errors.to_sentence
      result.record
    end
    add.("image", { media_asset_id: asset.id }, { "en" => { caption: "A picture", alt: "What it shows" } })
    section = add.("section", { settings: { "layout" => "three", "background" => "tinted", "width" => "full" } })
    add.("rich_text", { section_id: section.id, section_column: 1 }, { "en" => { body: rich_doc("### In a column\n\nLeft") } })
    add.("image", { section_id: section.id, section_column: 2, media_asset_id: asset.id })
    add.("post_list", { section_id: section.id, section_column: 3, settings: { "content_type" => "blog" } })
    add.("post_list", { settings: { "content_type" => "resume_entry" } })
    add.("post_list", { settings: { "content_type" => "now_update" } })
    add.("image")
    add.("rich_text", {}, { "en" => { body: rich_doc("Kept and ~~struck~~ words, a [link](https://example.com)\n\n- one\n- two\n\n> quoted") } })
    publish_changes(wide)

    result = Posts::Save.call(attributes: { content_type: "resume_entry", published: true,
      fields: { company: "Example Co", role_type: "ic", start_date: "2024-01-01", end_date: "" } }, translations: { "en" => { title: "Engineer" } })
    assert result.ok?, result.errors.to_sentence
    create_post(title: "Doing now", content_type: "now_update")
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

  test "its README says how to run it while writing, where the folder goes and that the templates are code" do
    scaffolded do |target, _written|
      readme = target.join("README.md").read

      assert_includes readme, "THEME_PATH=<this folder> bin/dev"
      assert_includes readme, "No `.rb` file"
      assert_includes readme, "run with the application's reach"
      assert_includes readme, "with the site's Dockerfile beside the folder, not in it"
    end
  end

  test "its stylesheet declares nothing and names every token of the contract" do
    scaffolded do |target, _written|
      css = target.join("assets/stylesheets/theme.css").read

      assert_empty css.gsub(%r{/\*.*?\*/}m, "").strip, "the stylesheet is a comment and nothing else: the site looks as before"
      Theme::Contract::TOKENS.each { |token| assert_includes css, token }
    end
  end

  test "a site under the folder it writes is drawn byte for byte as under the default theme: every block type, a section, the three lists, a post of each type, a 404 and two more languages" do
    paths = [ "/", "/blog", "/blog/first-post", "/wide", "/wide/engineer", "/wide/doing-now", "/de/", "/es/ancho", "/no-such-page" ]
    default = paths.index_with { |path| body_of(path) }
    # What the comparison is ON: each of these is on a compared page.
    { "/wide" => [ "content-block--image", "<s>struck</s>", "Engineer", "Updated ", "First post", "In a column", "<figcaption" ],
      "/wide/engineer" => [ "Engineer" ], "/wide/doing-now" => [ "Doing now" ], "/blog/first-post" => [ "First post" ],
      "/es/ancho" => [ "Ancho" ] }.each do |path, words|
      get path
      assert_response :success, path
      words.each { |word| assert_includes default.fetch(path), word, "#{path} does not draw #{word}: the comparison would be on less than it says" }
    end

    scaffolded do |target, _written|
      theme = Theme.load(ThemeFolder.new(target))
      definitions = BlockTypes.all.map { |definition| [ definition, :component ] } +
        ContentTypes.all.flat_map { |definition| [ [ definition, :list_component ], [ definition, :detail_component ] ] }
      own = definitions.map { |definition, role| theme.component_for(definition, role) }.select { |component| component.sidecar_files([ "erb" ]).first.to_s.start_with?(target.to_s) }
      assert_equal Theme::Contract::COMPONENTS.keys.sort, own.map { |component| component.name.underscore }.uniq.sort, "every component is drawn by the copy's template"

      Theme.with(theme) do
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
