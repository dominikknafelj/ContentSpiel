require "test_helper"

# The `:theme_choice` field type: a name from one of the lists the theme
# declares in theme.yml (`of: :section_styles` or `:icons`). The list is the
# theme's at the moment of the validation, never copied into the definition,
# and a name already stored stays valid whatever the theme says now.
class ContentModel::ThemeChoiceFieldTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :style, :theme_choice, of: :section_styles
    end
  end

  def fields(values, stored: {}) = ContentModel::FieldSet.for(@definition).new({}, {}, stored:).assign(values)

  test "a declared name, blank and the value already stored are valid; another unknown name is refused" do
    with_choices_theme do
      assert fields({ "style" => "services" }).valid?
      assert fields({ "style" => "" }).valid?
      assert fields({}).valid?
      assert fields({ "style" => "retired" }, stored: { "style" => "retired" }).valid?

      set = fields({ "style" => "retired" }, stored: { "style" => "other" })
      assert_not set.valid?
      assert_includes set.errors.details[:style].map { |detail| detail[:error] }, :inclusion
      assert_not fields({ "style" => "retired" }).valid?
    end
  end

  test "the options are asked at each validation, so a theme swapped afterwards is seen" do
    set = fields({ "style" => "services" })

    with_choices_theme { assert set.valid? }
    assert_not set.valid?, "the default theme declares no section style"
  end

  test "a theme choice needs of: naming section_styles or icons, and can't be translated" do
    definition = ContentModel::BlockTypeDefinition.new("sample")

    assert_raises(ArgumentError) { definition.field :style, :theme_choice }
    error = assert_raises(ArgumentError) { definition.field :style, :theme_choice, of: :page_templates }
    assert_match(/section_styles/, error.message)
    assert_match(/icons/, error.message)
    assert_raises(ArgumentError) { definition.field :style, :theme_choice, of: :icons, translated: true }
    assert_nothing_raised { definition.field :icon, :theme_choice, of: :icons }
  end

  test "a content type and a field group may not declare one" do
    [ ContentModel::ContentTypeDefinition, ContentModel::FieldGroupDefinition ].each do |kind|
      error = assert_raises(ArgumentError) { kind.new("sample").field :style, :theme_choice, of: :section_styles }
      assert_match(/choices for posts are not built/, error.message)
    end
  end

  test "asking the choices before anything assigned them raises with the way out" do
    saved = ContentModel.instance_variable_get(:@theme_choices)
    ContentModel.theme_choices = nil
    error = assert_raises(ContentModel::NoThemeChoices) { ContentModel.theme_choices }
    assert_match(/config\/initializers\/types.rb/, error.message)
  ensure
    ContentModel.theme_choices = saved
  end
end
