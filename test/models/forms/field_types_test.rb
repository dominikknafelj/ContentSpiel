require "test_helper"

# The form registry (forms plan, Task 1): the half of a form field's type
# that is a visitor's form's own. What a value IS stays `ContentModel::
# FieldTypes`' (`value_type`).
class Forms::FieldTypesTest < ActiveSupport::TestCase
  BUILT_INS = %w[short_text long_text email choice checkbox].freeze

  def field(name, **settings) = Forms::Field.from_h({ "key" => "f_abcd1234", "type" => name, "label" => { "en" => "L" }, "settings" => settings })

  def valid_type(name: "acme/rating", **changes)
    Forms::FieldType.new(
      name: name, value_type: :integer, label: "Rating", options: [], max_length: nil, summary: false,
      input: Blocks::FormFields::ShortTextComponent, display: ->(value, _field, locale:) { value.to_s }, **changes
    )
  end

  test "the five built-ins are registered in order, each with a ContentModel value type that is registered" do
    assert_equal BUILT_INS, Forms::FieldTypes.names

    Forms::FieldTypes.all.each do |type|
      assert_kind_of Forms::FieldType, type
      assert ContentModel::FieldTypes.find(type.value_type), "#{type.name}'s value type #{type.value_type.inspect} is a ContentModel field type"
      assert_operator type.input, :<, Blocks::FormFields::Base
      assert_respond_to type.display, :call
      assert_kind_of String, type.label
    end
    assert_equal %i[string text email select boolean], Forms::FieldTypes.all.map(&:value_type)
    assert_equal [ 500, 5_000 ], Forms::FieldTypes.all.first(2).map(&:max_length)
    assert_equal [ true, false, true, false, false ], Forms::FieldTypes.all.map(&:summary)
    assert_equal [ :choices, :display ], Forms::FieldTypes.fetch("choice").options
  end

  test "fetch names the known types for an unknown one" do
    error = assert_raises(KeyError) { Forms::FieldTypes.fetch("nonsense") }
    assert_includes error.message, "nonsense"
    BUILT_INS.each { |name| assert_includes error.message, name }
    assert_nil Forms::FieldTypes.find("nonsense")
  end

  test "a type of the wrong shape, a duplicate and an unknown value type are refused at registration" do
    saved = Forms::FieldTypes.all.dup
    assert_raises(ArgumentError) { Forms::FieldTypes.register("short_text") }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(name: "short_text")) }
    assert_includes assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(value_type: :nonsense)) }.message, "nonsense"
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(options: [ :colour ])) }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(max_length: 0)) }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(summary: "yes")) }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(input: String)) }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(display: "no")) }
    assert_raises(ArgumentError) { Forms::FieldTypes.register(valid_type(label: "")) }
    assert_equal saved, Forms::FieldTypes.all, "nothing refused was kept"

    Forms::FieldTypes.register(valid_type)
    assert_equal "acme/rating", Forms::FieldTypes.fetch("acme/rating").name
  ensure
    Rails.application.reloader.prepare!
  end

  test "every type answers display for a value of its own" do
    choice = field("choice", "choices" => [ { "key" => "c_aaaaaaaa", "label" => { "en" => "Yes please", "de" => "Ja bitte" } } ])

    assert_equal "Hello", Forms::FieldTypes.fetch("short_text").display.call("Hello", field("short_text"), locale: "en")
    assert_equal "Hello", Forms::FieldTypes.fetch("long_text").display.call("Hello", field("long_text"), locale: "en")
    assert_equal "a@b.co", Forms::FieldTypes.fetch("email").display.call("a@b.co", field("email"), locale: "en")
    assert_equal "Yes please", Forms::FieldTypes.fetch("choice").display.call("c_aaaaaaaa", choice, locale: "en")
    assert_equal "Ja bitte", Forms::FieldTypes.fetch("choice").display.call("c_aaaaaaaa", choice, locale: "de")
    assert_equal "Yes please", Forms::FieldTypes.fetch("choice").display.call("c_aaaaaaaa", choice, locale: "es"), "a language with no label falls back to the default"
    assert_equal "", Forms::FieldTypes.fetch("choice").display.call(nil, choice, locale: "en")
    assert_equal "c_zzzzzzzz", Forms::FieldTypes.fetch("choice").display.call("c_zzzzzzzz", choice, locale: "en"), "a key the form no longer has reads as it is"

    checkbox = Forms::FieldTypes.fetch("checkbox").display
    assert_equal [ "Yes", "No" ], [ checkbox.call(true, field("checkbox"), locale: "en"), checkbox.call(false, field("checkbox"), locale: "en") ]
    assert_equal "Yes", checkbox.call(true, field("checkbox"), locale: "xx"), "a language with no words reads English"
  end

  test "the registry is reset and filled with the built-ins again" do
    Forms::FieldTypes.reset!
    assert_empty Forms::FieldTypes.names
    Forms::FieldTypes.register_built_ins
    assert_equal BUILT_INS, Forms::FieldTypes.names
  ensure
    Rails.application.reloader.prepare!
  end
end
