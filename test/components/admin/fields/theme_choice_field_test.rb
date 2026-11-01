require "test_helper"

class Admin::Fields::ThemeChoiceFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def style = Field.new(name: "style", type: :theme_choice, options: { of: :section_styles, label: "Style" })

  def draw(field, value, theme: nil, locale: "en")
    render = -> { render_inline Admin::Fields::ThemeChoiceField.new(field:, form_name: "block[settings]", value:, locale:) }
    theme ? Theme.with(theme, &render) : render.call
  end

  test "no select without a choice: an empty list and no stored name draw nothing, label included" do
    draw(style, nil)

    assert_no_selector "select"
    assert_no_text "Style"
    assert_empty rendered_content.strip
    assert_not Admin::Fields::ThemeChoiceField.new(field: style, form_name: "x", value: nil, locale: "en").render?
  end

  test "one declared style draws Default and the label, in the theme's order" do
    draw(style, nil, theme: choices_theme)

    assert_selector "select[name='block[settings][style]'] option", count: 3
    assert_equal [ "Default", "Services", "Contact" ], page.all("option").map(&:text)
    assert_selector "option[value='']", text: "Default"
    assert_selector "option[value=services]"
    assert_no_selector "option[selected][value=services]"
  end

  test "the blank of an icon list says No icon" do
    draw(Field.new(name: "icon_name", type: :theme_choice, options: { of: :icons }), "brush", theme: choices_theme)

    assert_equal [ "No icon", "Design" ], page.all("option").map(&:text)
    assert_selector "option[selected][value=brush]"
  end

  test "a label is shown in the interface language, then English" do
    Theme.with(choices_theme) do
      I18n.with_locale(:de) do
        assert_equal "Kontakt", Admin::Fields::ThemeChoiceField.display(style, "contact")
        assert_equal "Services", Admin::Fields::ThemeChoiceField.display(style, "services")
      end
    end
  end

  test "a stored name the theme does not know is first, selected, by its name and marked not in this theme, also when the list is empty" do
    draw(style, "retired", theme: choices_theme)
    assert_equal [ "retired (not in this theme)", "Default", "Services", "Contact" ], page.all("option").map(&:text)
    assert_selector "option:first-child[selected][value=retired]"

    draw(style, "retired")
    assert_selector "select option", count: 2
    assert_selector "option:first-child[selected][value=retired]", text: "retired (not in this theme)"
  end

  test "a label that looks like markup is text" do
    Dir.mktmpdir("theme") do |dir|
      FileUtils.cp_r("#{PLAIN}/.", dir)
      File.write(File.join(dir, "theme.yml"), %(section_styles:\n  - name: odd\n    label: "<b>Bold</b> & <script>alert(1)</script>"\n))
      theme = Theme.load(ThemeFolder.new(Pathname(dir)))
      draw(style, nil, theme:)

      assert_no_selector "b"
      assert_no_selector "script", visible: :all
      assert_selector "option[value=odd]", text: "<b>Bold</b> & <script>alert(1)</script>"
    end
  end

  test "display is the label, the blank's word, or the name marked not in this theme" do
    field = style
    Theme.with(choices_theme) do
      assert_equal "Services", Admin::Fields::ThemeChoiceField.display(field, "services")
      assert_equal "Default", Admin::Fields::ThemeChoiceField.display(field, nil)
      assert_equal "retired (not in this theme)", Admin::Fields::ThemeChoiceField.display(field, "retired")
    end
  end
end
