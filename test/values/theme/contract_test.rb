require "test_helper"

# THE CONTRACT IS A PROMISE (theming spec §7 and "Risks"): every name in
# Theme::Contract is one a theme outside this repository relies on, and the
# CMS says in its release notes when one changes. These tests hold the list
# to the code, both ways: a name on the list that the code no longer has
# fails, and so does something a theme can reach that the list forgot.
#
# A BLOCK TYPE ADDED LATER joins by its declarations (block types spec,
# decisions 4 and 5): `t.theme_methods`, its component's line in
# `Theme::Contract.components`, and `t.tokens`, its lines in `themed_tokens`
# or `fixed_tokens`. The first test below fails until the first is there and
# the token test until the second is, each naming the missing entry; the two
# tests after the first show that it can fail. The built-in types' part is
# held by the ledger (test/values/theme/contract_ledger_test.rb).
class Theme::ContractTest < ActiveSupport::TestCase
  include ComponentTestHelper

  TOKENS_CSS = Rails.root.join("app/assets/tailwind/themes/default/tokens.css")
  COLOUR = /#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/

  # Every registered type's components, by the path the contract names them
  # under: derived over every registered type, outside ones included (block
  # types spec, "Tests"), since an outside type's line is read from its own
  # declaration as a built-in's is.
  def registry_components
    blocks = BlockTypes.all.map(&:component)
    posts = ContentTypes.all.flat_map { |definition| [ definition.list_component, definition.detail_component ] }
    (blocks + posts).compact.uniq.map { |component| component.name.underscore }.sort
  end

  # The one comparison of the registries with the list, as an assertion of
  # its own so that the tests below can show it failing.
  def assert_every_registered_component_is_listed
    missing = registry_components - Theme::Contract.components.keys
    assert_empty missing,
      "Theme::Contract.components has no entry for #{missing.map(&:inspect).join(", ")}: a block type hands that component out " \
      "without `theme_methods`, so a theme cannot replace its template. Declare `t.theme_methods` in its definition, " \
      "with the methods its template may call"
  end

  # A component nobody has written, under the name a type's own would have.
  def unlisted_component(name)
    Class.new(ApplicationComponent) { define_singleton_method(:name) { name } }
  end

  test "every component a type registry hands out is on the list, and the list holds nothing else" do
    assert_every_registered_component_is_listed

    left_over = Theme::Contract.components.keys - registry_components
    assert_empty left_over, "Theme::Contract.components lists #{left_over.inspect}, which no block or content type hands out"
  end

  # The type is one nobody will build. It was "code" with
  # `Blocks::CodeComponent` while the Code block was the next thing to join;
  # the day that block was registered this test raised `DuplicateType`, and
  # with its line in the contract the assertion would no longer have failed.
  test "a block type registered with a component the list does not hold fails, and the message names the missing entry" do
    component = unlisted_component("Blocks::MarqueeComponent")
    BlockTypes.register("marquee") do |t|
      t.label "Marquee"
      t.component component
    end

    error = assert_raises(Minitest::Assertion) { assert_every_registered_component_is_listed }

    assert_includes error.message, %(Theme::Contract.components has no entry for "blocks/marquee_component")
    assert_includes error.message, "Declare `t.theme_methods` in its definition"
  ensure
    Rails.application.reloader.prepare!
  end

  test "a content type registered with a list component the list does not hold fails the same way" do
    component = unlisted_component("Posts::GalleryListComponent")
    ContentTypes.register("gallery") do |t|
      t.label "Gallery"
      t.list_component component
      t.detail_component Posts::DetailComponent
    end

    error = assert_raises(Minitest::Assertion) { assert_every_registered_component_is_listed }

    assert_includes error.message, %(Theme::Contract.components has no entry for "posts/gallery_list_component")
  ensure
    Rails.application.reloader.prepare!
  end

  test "every listed component has its default template and every method its template may call" do
    Theme::Contract.components.each do |path, methods|
      assert Theme::Contract.template_for(path).file?, "#{path} has no default template"
      component = path.camelize.constantize
      methods.each do |name|
        assert component.method_defined?(name) || component.private_method_defined?(name), "#{component} has no #{name}"
      end
    end
    Theme::Contract::COMPONENT_HELPERS.each do |name|
      assert ApplicationComponent.method_defined?(name), "a component's template cannot call #{name}"
    end
  end

  # THE CODE BLOCK, the first block to join (decision 18, code block spec
  # §5): its component's line and its seven tokens. Beside the spec's
  # eight names the line holds `string`: a theme has no Ruby of its own,
  # and the copy script takes its words from the template. NOT on it, and
  # not methods of the component at all: `head_attributes`, `file_id` and
  # `bare?`. They were the default template's layout (when its head strip
  # is the script's to show, what its file name's id is), which is the
  # thing a replaced template changes; the default template writes both
  # out from promised names, so `theme:new`'s copy shows an author how.
  test "the Code block is in the contract: its template is replaceable with the methods it may call, and its seven syntax tokens are themed tokens in the highlighter's order" do
    assert_equal %w[block page lines code language language_label filename caption string], Theme::Contract.components.fetch("blocks/code_component")
    assert_equal CodeHighlight::ROLES.map { |role| "syn-#{role}" }, Theme::Contract.themed_tokens.grep(/\Asyn-/)
    CodeHighlight::ROLES.each { |role| assert_includes Theme::Contract.tokens, "--th-syn-#{role}" }
    assert_empty Theme::Contract.fixed_tokens.grep(/\Asyn-/), "a syntax colour has a light and a dark value"
    assert_empty Theme::Contract.components.fetch("blocks/code_component") & %w[head_attributes file_id bare? settings]
    %i[head_attributes file_id bare?].each do |name|
      assert_not Blocks::CodeComponent.method_defined?(name) || Blocks::CodeComponent.private_method_defined?(name), "#{name} is the default template's own layout, written out in the template"
    end
  end

  # The copy `theme:new` writes is the contract's example: a method of the
  # component that a default template calls and its line does not name
  # would put every scaffolded theme on a name the CMS may rename. Read
  # from each template's ERB tags, the words of their strings left out: a
  # word there that is a method the component's own class defines. Not
  # seen: a call inside a string's interpolation (the Code block's
  # `"code-#{block.id}-file"`), one written `self.name`, and a method a
  # component inherits from a base of its own.
  def component_methods_called(path)
    component = path.camelize.constantize
    own = (component.instance_methods(false) + component.private_instance_methods(false)).map(&:to_s) - %w[initialize render? call]
    code = Rails.root.join("app/components/#{path}.html.erb").read.scan(/<%(?!#)(.*?)%>/m).join("\n").gsub(/"[^"]*"/, %(""))
    own.select { |name| code.match?(/(?<![\w.:@])#{Regexp.escape(name)}(?![\w:])/) }
  end

  test "a default component template calls no method of its component that its line does not name" do
    Theme::Contract.components.each do |path, methods|
      assert_empty component_methods_called(path) - methods, "#{path}.html.erb calls a method of its component that Theme::Contract.components does not list for it"
    end
    assert_equal %w[caption filename language_label lines string], component_methods_called("blocks/code_component").sort,
      "the reading sees what the Code block's template calls (and so could fail)"
  end

  # What the reference promises of those methods: each is safe for an empty
  # block (a theme's template may call it without a guard), and the four
  # words are there in a language that has no file of its own.
  test "each method the Code block's template may call answers for a block with no settings, and its four words are never missing" do
    page = root_page
    component = Blocks::CodeComponent.new(block: ContentBlock.new(owner: page, block_type: "code"), page: page)
    render_inline(component)

    assert_equal [], component.send(:lines)
    %i[code language language_label filename caption].each { |name| assert_nil component.send(name), name.to_s }
    assert_equal false, component.render?, "and the component draws nothing without code, so a template never meets one"
    I18n.with_locale(:de) do
      assert_equal [ "Copy", "Copy code", "Copied", "Not copied" ], %i[copy copy_code copied failed].map { |key| component.send(:string, key) }
    end
  end

  test "every listed template has its default under app/views, and says what it is" do
    Theme::Contract::TEMPLATES.each do |path, description|
      assert Rails.root.join("app/views", path).file?, "#{path} has no default"
      assert_operator description.length, :>, 15, "#{path} needs its description"
    end
  end

  test "what the layout renders of the theme's is on the list, and what is the CMS's is not" do
    %w[layouts/public/_frame layouts/public/_title layouts/public/_icons layouts/public/_head pages/show pages/not_found].each do |name|
      assert Theme::Contract::TEMPLATES.key?("#{name}.html.erb"), "#{name} is not replaceable"
    end
    %w[layouts/application pages/_seo_meta shared/_theme_head layouts/public/_preview_banner].each do |name|
      assert_not Theme::Contract::TEMPLATES.key?("#{name}.html.erb"), "#{name} is the CMS's and must not be replaceable"
    end
  end

  test "every listed helper is one a template can call" do
    available = ThemeHelper.public_instance_methods + PagesHelper.public_instance_methods

    Theme::Contract::HELPERS.each { |name| assert_includes available, name.to_sym }
  end

  # A type with an owner's own stylesheet (one outside the default theme's
  # folder) defines its tokens there, in the same three blocks; every other
  # type's are in tokens.css (block types spec, decision 7). Today no type
  # has an owner, so the second half runs from Task 6 on (its gallery).
  test "every declared token is defined, a themed one for light and for dark, and no --th- name is undeclared" do
    default_folder = Rails.root.join("app/assets/tailwind/themes/default")
    owned = BlockTypes.all.select { |definition| (path = definition.stylesheet_path) && path.dirname != default_folder }
    owned.each do |definition|
      sheet = definition.stylesheet_path.read
      light = sheet[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1].to_s.scan(/(--th-[\w-]+):/).flatten.sort
      dark = sheet[/^\[data-theme="dark"\]\s*\{(.*?)\}/m, 1].to_s.scan(/(--th-[\w-]+):/).flatten.sort
      fixed = sheet[/^:root \{(.*?)\}/m, 1].to_s.scan(/(--th-[\w-]+):/).flatten.sort
      themed = definition.themed_tokens.map { |name| "--th-#{name}" }.sort
      assert_equal themed, light, "#{definition.name}: the light block of its stylesheet defines its themed tokens"
      assert_equal themed, dark, "#{definition.name}: the dark block of its stylesheet defines its themed tokens"
      assert_equal definition.fixed_tokens.map { |name| "--th-#{name}" }.sort, fixed, "#{definition.name}: its :root block defines its fixed tokens"
    end
    owned_themed = owned.flat_map(&:themed_tokens)
    owned_fixed = owned.flat_map(&:fixed_tokens)
    contract_themed = Theme::Contract.themed_tokens - owned_themed
    contract_fixed = Theme::Contract.fixed_tokens - owned_fixed

    css = TOKENS_CSS.read
    names = ->(block) { block.to_s.scan(/(--th-[\w-]+):/).flatten }
    light = names.(css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1])
    dark = names.(css[/^\[data-theme="dark"\]\s*\{(.*?)\}/m, 1])
    fixed = names.(css[/^:root \{(.*?)\}/m, 1])
    own = ->(list) { list.grep(Theme::Contract::OWN_TOKENS) }
    prefixed = ->(list) { list.map { |name| "--th-#{name}" }.sort }
    # Which names one side has and the other has not, so a token added to the
    # stylesheet without its line (or the reverse) is named in the failure.
    differ = lambda do |list, block, constant, where|
      listed = prefixed.(list)
      defined = (block - own.(block)).sort
      assert_equal listed, defined,
        "Theme::Contract.#{constant.downcase} and #{where} of tokens.css differ. Defined but not listed (add each to SHARED_#{constant} in " \
        "app/values/theme/contract.rb, or to the `t.tokens` of the type it belongs to, without the --th- prefix): #{(defined - listed).inspect}. " \
        "Listed but not defined: #{(listed - defined).inspect}"
    end

    assert_not_empty light
    assert_not_empty dark
    assert_not_empty fixed
    differ.(contract_themed, light, "THEMED_TOKENS", "the light block")
    differ.(contract_themed, dark, "THEMED_TOKENS", "the dark block")
    differ.(contract_fixed, fixed, "FIXED_TOKENS", "the fixed block")
    assert_equal Theme::Contract.tokens.sort, (prefixed.(Theme::Contract.themed_tokens) + prefixed.(Theme::Contract.fixed_tokens)).sort
    assert_equal %w[--th-ph-a --th-ph-b --th-preview-bg --th-preview-ink], own.(light + fixed).sort, "the CMS's own tokens"
    assert_empty Theme::Contract.tokens.grep(Theme::Contract::OWN_TOKENS)
    assert_equal names.(css).uniq.sort, (light + dark + fixed).uniq.sort, "a --th- token is defined outside the three blocks"
  end

  test "the default theme's styles and templates hold no colour literal: tokens.css is the one place" do
    styles = (Rails.root.glob("app/assets/tailwind/themes/default/*.css") - [ TOKENS_CSS ] + BlockTypes.all.filter_map(&:stylesheet_path)).uniq
    styles.each { |path| assert_no_match COLOUR, path.read, "#{path.basename} holds a colour" }

    templates = Theme::Contract::TEMPLATES.keys.map { |path| Rails.root.join("app/views", path) } +
      Theme::Contract.components.keys.map { |path| Rails.root.join("app/components/#{path}.html.erb") }
    templates.each do |path|
      assert_no_match(/\[#\h{3,8}\]|\brgba?\(|\bhsla?\(|\boklch\(|style=/, path.read, "#{path} holds a colour or an inline style")
    end
  end

  test "the default theme's tokens file imports nothing and names no block" do
    css = TOKENS_CSS.read

    assert_no_match(/@import/, css)
    assert_no_match(/content-block|content-section|cs-prose/, css)
  end

  test "a rendered text is the elements the contract lists, under no class of its own" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0,
      body: rich_doc("## Two\n\n### Three\n\n#### Four\n\nA **bold** *slanted* ~~struck~~ `code` [link](https://example.org) line.\n\n" \
                     "- one\n\n1. first\n\n> quoted\n\n```\nsource\n```\n\n---"))

    render_inline(Blocks::RichTextComponent.new(block: block, page: page))
    body = Nokogiri::HTML5.fragment(rendered_content).at_css(".cs-prose")

    %w[h2 h3 h4 p ul ol li blockquote a strong em s code pre hr].each do |element|
      assert_includes Theme::Contract::RICH_TEXT, element
      assert body.at_css(element), "the text was rendered with no <#{element}>"
    end
    assert_includes Theme::Contract::RICH_TEXT, "pre code"
    assert body.at_css("pre code")
    assert_empty body.css("[class]").map { |node| node["class"] }, "a text's own elements carry no class: a theme styles them by element"
    assert_empty body.css("*").map(&:name).uniq - Theme::Contract::RICH_TEXT, "an element a text renders is not in Theme::Contract::RICH_TEXT"
  end
end
