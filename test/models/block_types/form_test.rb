require "test_helper"

# The Form block's type (forms plan, Task 7): one field naming a form by its
# id, its component, the methods its template may call and its six tokens.
class BlockTypes::FormTest < ActiveSupport::TestCase
  test "the form type declares one form field, its component, theme methods and tokens" do
    definition = BlockTypes.fetch(:form)

    assert_equal [ %w[form_id form] ], definition.fields.map { |field| [ field.name, field.type.to_s ] }
    assert definition.fields.none?(&:required?), "the picker makes an empty block first"
    assert definition.fields.none?(&:translated?), "a form is the same in every language"
    assert_equal Blocks::FormComponent, definition.component
    assert_equal %w[block page form_name fields action locale page_id drawn honeypot submit_label thank_you unavailable string], definition.theme_methods
    assert_equal %w[form-field-ground form-field-line form-field-focus form-error form-done-ground form-done-line], definition.themed_tokens
    assert_empty definition.fixed_tokens
    assert_equal "clipboard_list", definition.icon
    assert_equal Rails.root.join("app/assets/tailwind/themes/default/form.css"), definition.stylesheet_path
    assert definition.sample.form, "the sample makes a form of its own"
    assert_equal [ "Your name", "Send" ], definition.sample.shows
  end

  test "the Form block stands after the Table in the picker, and the containers stay last" do
    names = BlockTypes.built_in_names
    assert_equal names.index("table") + 1, names.index("form")
    assert_equal "section", names.last
  end

  test "summary names the form, No form chosen and The form is gone" do
    form = forms(:contact)
    block = root_page.content_blocks.new(block_type: "form", settings: { "form_id" => form.id.to_s })
    assert_equal [ [ :text, "Contact" ] ], BlockTypes::Form.summary(block, locale: "en")

    assert_equal [ [ :hint, :no_form ] ], BlockTypes::Form.summary(root_page.content_blocks.new(block_type: "form", settings: {}), locale: "en")

    form.update_columns(trashed_at: Time.current) # version: none (a test's row)
    assert_equal [ [ :hint, :gone ] ], BlockTypes::Form.summary(block, locale: "en")
    block.settings = { "form_id" => "999999" }
    assert_equal [ [ :hint, :gone ] ], BlockTypes::Form.summary(block, locale: "en")

    %w[no_form gone].each do |key|
      assert I18n.exists?("admin.components.editor_screen.tile_summary.types.form.#{key}", :en), "the tile has words for #{key}"
    end
  end

  test "a form field stores a form's id as digits, and anything else as nothing" do
    type = ContentModel::FieldTypes.fetch(:form)

    assert_equal "12", type.cast.call("12")
    assert_equal "12", type.cast.call(12)
    assert_equal "12", type.cast.call(" 12 ")
    [ "12a", "-3", "1.5", "x", "0", "" ].each { |value| assert_nil type.cast.call(value), value.inspect }
    assert_not type.translatable
    assert_equal :value, type.audit
    assert_raises(ArgumentError) { BlockTypes.register("test/formish") { |t| t.field :form_id, :form, translated: true } }
  ensure
    Rails.application.reloader.prepare!
  end
end
