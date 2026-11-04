require "test_helper"

class Forms::FieldTest < ActiveSupport::TestCase
  def choice_hash
    { "key" => "f_abcd1234", "type" => "choice", "required" => true, "label" => { "en" => "Topic", "de" => "Thema" }, "help" => { "en" => "Pick one" },
      "settings" => { "display" => "radios", "choices" => [ { "key" => "c_aaaaaaaa", "label" => { "en" => "Press", "de" => "Presse" } }, { "key" => "c_bbbbbbbb", "label" => { "en" => "Other" } } ] } }
  end

  test "a label falls back to the default language, and is nil when none is written" do
    field = Forms::Field.from_h(choice_hash)

    assert_equal "Thema", field.label_in("de")
    assert_equal "Topic", field.label_in("es"), "the default language is the fallback"
    assert_equal "Pick one", field.help_in("de")
    assert_nil Forms::Field.from_h("key" => "f_abcd1234", "type" => "short_text").label_in("en")
    assert_nil Forms::Field.from_h("key" => "f_abcd1234", "type" => "short_text", "label" => { "en" => "  " }).label_in("en"), "blank is not written"
    assert_nil Forms::Field.from_h("key" => "f_abcd1234", "type" => "short_text").help_in("en")

    press, other = Forms::Field.from_h(choice_hash).choices
    assert_equal [ "Presse", "Press" ], [ press.label_in("de"), press.label_in("es") ]
    assert_equal "Other", other.label_in("de")
  end

  test "from_h and to_h round-trip a choice field" do
    field = Forms::Field.from_h(choice_hash)

    assert_equal choice_hash, field.to_h
    assert_equal field, Forms::Field.from_h(field.to_h)
    assert_equal [ Forms::Choice ], field.choices.map(&:class).uniq
    assert_equal %w[c_aaaaaaaa c_bbbbbbbb], field.choices.map(&:key)
    assert field.required
    assert_equal "choice", field.field_type.name
  end

  test "from_h reads a hash with symbol keys and missing parts" do
    field = Forms::Field.from_h(key: "f_abcd1234", type: "short_text")

    assert_equal false, field.required
    assert_equal({}, field.label)
    assert_equal({}, field.settings)
    assert_empty field.choices
  end

  test "definition_field is the content model's field: the key as its name, the value type, the limit and the choice keys" do
    short = Forms::Field.from_h("key" => "f_abcd1234", "type" => "short_text").definition_field
    assert_equal [ "f_abcd1234", :string, 500 ], [ short.name, short.type, short.options[:max] ]

    long = Forms::Field.from_h("key" => "f_abcd1234", "type" => "long_text").definition_field
    assert_equal [ :text, 5_000 ], [ long.type, long.options[:max] ]

    choice = Forms::Field.from_h(choice_hash).definition_field
    assert_equal [ :select, %w[c_aaaaaaaa c_bbbbbbbb] ], [ choice.type, choice.options[:options] ]
    assert_nil choice.options[:max]
    assert_equal :email, Forms::Field.from_h("key" => "f_abcd1234", "type" => "email").definition_field.type
  end

  test "new keys match KEY_FORMAT and differ" do
    keys = Array.new(50) { Forms::Field.new_key }

    keys.each { |key| assert_match Forms::Field::KEY_FORMAT, key }
    assert_equal keys.size, keys.uniq.size
    assert_equal 10, keys.first.length
    assert_no_match Forms::Field::KEY_FORMAT, "f_ABCD1234"
    assert_no_match Forms::Field::KEY_FORMAT, "f_abcd123"
    assert_no_match Forms::Field::KEY_FORMAT, "f_abcd1234\n"
    assert_match(/\Ac_[a-z0-9]{8}\z/, Forms::Choice.new_key)
  end

  test "a public field carries the ids a form placed twice on a page keeps apart" do
    field = Forms::Field.from_h(choice_hash)
    one = Forms::PublicField.new(field: field, locale: "de", form_id: 7, place: 11)
    two = Forms::PublicField.new(field: field, locale: "de", form_id: 7, place: 12)

    assert_equal "answers[f_abcd1234]", one.name
    assert_equal "form-11-f_abcd1234", one.id
    assert_equal "form-11-f_abcd1234-error", one.error_id
    assert_equal "form-11-f_abcd1234-help", one.help_id
    assert_not_equal one.id, two.id
    assert_equal [ "Thema", "Pick one", true, "radios", "choice" ], [ one.label, one.help, one.required?, one.display, one.type_name ]
    assert_equal "dropdown", PublicFieldHelper.dropdown.display
    assert_nil one.max_length
    assert_equal Blocks::FormFields::ChoiceComponent, one.input
  end

  module PublicFieldHelper
    def self.dropdown = Forms::PublicField.new(field: Forms::Field.from_h("key" => "f_abcd1234", "type" => "choice"), locale: "en", form_id: 1, place: 1)
  end
end
