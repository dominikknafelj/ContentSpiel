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

  # On a reload nothing may leave `prepare`: an exception there stops the
  # chain of prepare blocks and leaves the application half prepared. So
  # whatever the check raises, a fault of its own included, is kept as the
  # refusal. At boot a fault of the check is loud, as it is.
  test "on a reload prepare keeps whatever the check raises as the refusal, with what was raised in the message; at boot it is raised as it is" do
    with_theme_copy do |dir|
      folder = ThemeFolder.new(dir)

      [ KeyError.new("key not found: \"notes.txt\""), NoMethodError.new("undefined method 'start_with?' for nil"),
        Errno::ENOENT.new("views/pages/show.html.erb") ].each do |fault|
        with_singleton_override(Theme::Check, :problems, ->(*, **) { raise fault }) do
          assert_same fault, assert_raises(fault.class) { Theme.prepare(folder, reload: false) }

          refused = Theme.prepare(folder, reload: true)
          assert_instance_of ThemeFolder::Invalid, refused.refusal
          assert_includes refused.refusal.message, "THEME_PATH (#{dir}) could not be checked"
          assert_includes refused.refusal.message, "#{fault.class}: #{fault.message}"
          assert_not refused.configured?, "a folder that could not be checked draws nothing"
        end
      end
    end
  end

  # Not a proof that the initializer runs: `Theme.current` answers a default
  # theme by itself when nothing was assigned. That proof is the production
  # boots (`test/lib/production_boot_test.rb`).
  test "under test the application's theme is the default: THEME_PATH is not read" do
    assert_instance_of Theme, Theme.current
    assert_not Theme.current.configured?
  end

  test "a theme answers its choices, a theme without a folder and a refused theme the default's" do
    default = Theme::Declarations.default

    assert_equal default["page_templates"], Theme.new.choices(:page_templates)
    assert_equal default["page_templates"], Theme.new(refusal: ThemeFolder::Invalid.new("no")).choices("page_templates")
    assert_equal default["page_templates"], plain_theme.choices(:page_templates)
    assert_empty plain_theme.choices(:section_styles)

    theme = choices_theme

    assert_equal %w[services contact], theme.choices(:section_styles).map(&:name)
    assert_equal "Kontakt", theme.choice(:section_styles, "contact").label_for("de")
    assert_equal "Contact", theme.choice("section_styles", :contact).label_for("es")
    assert_nil theme.choice(:section_styles, "missing")
    assert_equal %w[brush], theme.choices(:icons).map(&:name)
  end

  test "icon_svg inlines a declared icon once per theme and is nil for blank and unknown names" do
    theme = choices_theme
    file = ThemeTestHelper::CHOICES.join("assets/images/icons/brush.svg")
    icon = theme.icon_svg("brush")

    assert_predicate icon, :html_safe?
    assert_equal Theme::IconFile.inline(file.read), icon
    assert_includes icon, %(<svg aria-hidden="true" focusable="false")
    assert_same icon, theme.icon_svg(:brush), "read once per theme"
    [ nil, "", "  ", "missing" ].each { |name| assert_nil theme.icon_svg(name), name.inspect }
    assert_nil Theme.new.icon_svg("brush"), "the default theme declares no brush"
  end

  test "icon_svg is nil for an icon whose file no longer passes the fence, and reads a default icon from the CMS's images" do
    with_theme_copy do |dir|
      dir.join("assets/images/icons").mkpath
      icon = dir.join("assets/images/icons/brush.svg")
      icon.write(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0"/></svg>))
      dir.join("theme.yml").write("icons:\n  - name: brush\n    label: Brush\n    file: icons/brush.svg\n")
      theme = Theme.load(ThemeFolder.new(dir))
      icon.write(%(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>))

      assert_nil theme.icon_svg("brush"), "the bytes inlined are the bytes fenced"
    end

    # The default theme's own icons are among the CMS's images; one is put
    # there for this test under a name nothing else uses.
    name = "theme-test-#{SecureRandom.hex(6)}.svg"
    own = Rails.root.join("app/assets/images", name)
    own.write(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0"/></svg>))
    arrow = Theme::Choice.new(list: "icons", name: "arrow", labels: { "en" => "Arrow" }, fields: [], file: name, from: :default)
    theme = Theme.new(path: ThemeTestHelper::CHOICES, declarations: { "icons" => [ arrow ] })

    assert_equal Theme::IconFile.inline(own.read), theme.icon_svg("arrow")
    assert_equal name, theme.icon_asset("arrow")
  ensure
    own&.delete if own&.exist?
  end

  test "icon_svg draws no icon, and raises nothing, when the file cannot be read or taken apart" do
    # The suite has no minitest/mock: the module's own method is put back.
    inline = Theme::IconFile.method(:inline)
    [ Errno::EACCES, IOError, ArgumentError ].each do |error|
      theme = choices_theme
      Theme::IconFile.define_singleton_method(:inline) { |_| raise error }

      assert_nil theme.icon_svg("brush"), error.name
    end
  ensure
    Theme::IconFile.define_singleton_method(:inline, inline)
  end

  test "icon_asset is the served path of the theme's file" do
    theme = choices_theme

    assert_equal "icons/brush.svg", theme.icon_asset("brush")
    assert_match %r{\A/assets/icons/brush-\h+\.svg\z}, ActionController::Base.helpers.image_path(theme.icon_asset("brush"))
    assert_nil theme.icon_asset("missing")
    assert_nil theme.icon_asset(nil)
  end
end
