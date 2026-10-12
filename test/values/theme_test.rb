require "test_helper"

# The one seam through which a block's, a post list's and a post's template
# is replaced (theming spec §3). ViewComponent finds a template beside its
# class and never asks the view path, so `Theme#component_for` answers a
# class of the theme's own that carries the theme's template. These tests are
# the proof that the gem allows it, and they fail on the day an upgrade
# changes `sidecar_files`.
class ThemeTest < ActiveSupport::TestCase
  include ComponentTestHelper

  setup do
    @page = root_page
    @block = @page.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello there"))
    @definition = @block.definition
  end

  def draw(component_class) = render_inline(component_class.new(block: @block, page: @page))

  test "the same block is drawn by two themes and by the default in one process, in any order" do
    with_theme_copy do |dir|
      dir.join("components/blocks/rich_text_component.html.erb").write(%(<section class="other-text"><%= rich_text(block) %></section>\n))
      plain = plain_theme.component_for(@definition)
      other = Theme.new(path: dir).component_for(@definition)
      default = Theme.new.component_for(@definition)

      [ plain, default, other, plain, other, default ].each do |component_class|
        draw(component_class)

        assert_text "Hello there"
        assert_selector "div.plain-text", count: component_class == plain ? 1 : 0
        assert_selector "section.other-text", count: component_class == other ? 1 : 0
        assert_selector "div.cs-prose", count: component_class == default ? 1 : 0
      end
    end
  end

  test "the component's own class keeps its own template after a theme's class was drawn" do
    draw(plain_theme.component_for(@definition))
    assert_selector "div.plain-text"

    draw(Blocks::RichTextComponent)

    assert_selector "div.cs-prose", text: "Hello there"
    assert_no_selector ".plain-text"
  end

  test "a template the theme does not hold is the definition's own class, and a held one is a class of its own" do
    image = BlockTypes.find("image")

    assert_same Blocks::ImageComponent, plain_theme.component_for(image)
    assert_same Blocks::RichTextComponent, Theme.new.component_for(@definition)

    themed = plain_theme.component_for(@definition)
    assert_operator themed, :<, Blocks::RichTextComponent
    assert_equal "Blocks::RichTextComponent", themed.name
    assert_equal "blocks/rich_text_component", themed.virtual_path
    assert_equal Blocks::RichTextComponent.identifier, themed.identifier
  end

  test "one theme answers one class per component, and a theme built again answers a new one" do
    theme = plain_theme

    assert_same theme.component_for(@definition), theme.component_for(@definition)
    assert_not_same theme.component_for(@definition), plain_theme.component_for(@definition)
  end

  test "a theme built again draws the template as it is now" do
    with_theme_copy do |dir|
      file = dir.join("components/blocks/rich_text_component.html.erb")
      draw(Theme.new(path: dir).component_for(@definition))
      assert_selector "div.plain-text"

      file.write(%(<div class="plain-text-two"><%= rich_text(block) %></div>\n))
      draw(Theme.new(path: dir).component_for(@definition))

      assert_selector "div.plain-text-two", text: "Hello there"
    end
  end

  test "the other roles go through the same seam: a post list's and a post's component" do
    blog = ContentTypes.find("blog")

    assert_same Posts::BlogListComponent, Theme.new.component_for(blog, :list_component)
    assert_same Posts::DetailComponent, Theme.new.component_for(blog, :detail_component)
    assert_same Posts::DetailComponent, plain_theme.component_for(blog, :detail_component)
  end

  test "a theme's block template that raises names the theme's file" do
    with_theme_copy do |dir|
      dir.join("components/blocks/rich_text_component.html.erb").write("<div><%= no_such_helper_anywhere %></div>\n")

      error = assert_raises(NameError) { draw(Theme.new(path: dir).component_for(@definition)) }

      assert_includes error.backtrace.join("\n"), dir.join("components/blocks/rich_text_component.html.erb").to_s
    end
  end

  test "template_for answers the theme's file for a component, and nil without one or without a theme" do
    assert_equal ThemeTestHelper::PLAIN.join("components/blocks/rich_text_component.html.erb"), plain_theme.template_for(Blocks::RichTextComponent)
    assert_nil plain_theme.template_for(Blocks::ImageComponent)
    assert_nil Theme.new.template_for(Blocks::RichTextComponent)
  end

  test "with swaps the current theme for a block and puts the old one back, also when the block raises" do
    before = Theme.current
    theme = plain_theme

    Theme.with(theme) { assert_same theme, Theme.current }
    assert_same before, Theme.current

    assert_raises(RuntimeError) { Theme.with(theme) { raise "stop" } }
    assert_same before, Theme.current
  end

  test "a theme says its name, its views and its fingerprint" do
    assert_equal "plain", plain_theme.name
    assert_equal ThemeTestHelper::PLAIN.join("views"), plain_theme.views_path
    assert plain_theme.configured?

    assert_equal "default", Theme.new.name
    assert_nil Theme.new.views_path
    assert_equal "default", Theme.new.fingerprint
    assert_not Theme.new.configured?
  end

  # `PublicPageRendering` asks for this on every public request.
  test "whether the theme has a views folder is asked of the filesystem once per Theme, not once per request" do
    with_theme_copy do |dir|
      theme = Theme.new(path: dir)
      assert_equal dir.join("views").to_s, theme.views_directory

      FileUtils.rm_r(dir.join("views"))

      assert_equal dir.join("views").to_s, theme.views_directory, "the same Theme asked the filesystem again"
      assert_nil Theme.new(path: dir).views_directory, "a theme with no views folder has none to look in"
    end
    assert_nil Theme.new.views_directory
  end

  test "load builds a theme from a folder: its path, its fingerprint and how many templates it brings" do
    folder = ThemeFolder.new(ThemeTestHelper::PLAIN)
    theme = Theme.load(folder)

    assert_equal folder.path, theme.path
    assert_equal folder.fingerprint, theme.fingerprint
    assert_equal folder.templates.size, theme.template_count
    assert_operator theme.template_count, :>, 0

    default = Theme.load(ThemeFolder.new(nil))
    assert_not default.configured?
    assert_equal "default", default.fingerprint
    assert_equal 0, default.template_count
  end

  test "prepare is load at boot, and on a reload a refused folder is a theme that remembers why and brings nothing" do
    with_theme_copy do |dir|
      sound = Theme.prepare(ThemeFolder.new(dir), reload: true)
      assert sound.configured?
      assert_nil sound.refusal

      dir.join("views/pages/shwo.html.erb").write("x")
      folder = ThemeFolder.new(dir)
      assert_raises(ThemeFolder::Invalid) { Theme.prepare(folder, reload: false) }

      refused = Theme.prepare(folder, reload: true)
      assert_instance_of ThemeFolder::Invalid, refused.refusal
      assert_includes refused.refusal.message, "views/pages/shwo.html.erb is not part of the theme contract"
      assert_not refused.configured?, "a refused folder draws nothing"
      assert_nil refused.views_directory
      assert_same Blocks::RichTextComponent, refused.component_for(BlockTypes.fetch("rich_text"))
    end
  end

  test "a folder that stops being readable as one is refused the same way on a reload" do
    with_theme_copy do |dir|
      folder = ThemeFolder.new(dir)
      File.symlink("/etc/hosts", dir.join("views/theme/_hosts.html.erb"))

      assert_raises(ThemeFolder::Invalid) { Theme.prepare(folder, reload: false) }
      assert_includes Theme.prepare(folder, reload: true).refusal.message, "outside the theme folder"
    end
  end

  test "the application's theme is loaded when it is prepared, and under test it is the default" do
    assert_instance_of Theme, Theme.current
    assert_not Theme.current.configured?
  end
end
