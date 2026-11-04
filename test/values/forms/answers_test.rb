require "test_helper"

class Forms::AnswersTest < ActiveSupport::TestCase
  def fields
    [
      Forms::Field.from_h("key" => "f_name0001", "type" => "short_text", "required" => true, "label" => { "en" => "Name", "de" => "Name (de)" }),
      Forms::Field.from_h("key" => "f_mail0002", "type" => "email", "label" => { "en" => "Email" }),
      Forms::Field.from_h("key" => "f_text0003", "type" => "long_text", "label" => { "en" => "Message" }),
      Forms::Field.from_h("key" => "f_pick0004", "type" => "choice", "label" => { "en" => "Topic" },
        "settings" => { "display" => "radios", "choices" => [ { "key" => "c_aaaaaaaa", "label" => { "en" => "Press", "de" => "Presse" } } ] }),
      Forms::Field.from_h("key" => "f_okay0005", "type" => "checkbox", "required" => true, "label" => { "en" => "I agree" })
    ]
  end

  # String keys written without braces arrive as keywords.
  def clean(raw = nil, locale: "en", **answers) = Forms::Answers.clean(fields, { "f_okay0005" => "1" }.merge(raw || answers), locale: locale)

  test "a required short text left blank is :blank and the typed values are kept" do
    result = clean("f_name0001" => "  ", "f_mail0002" => "ada@example.com")

    assert_equal({ "f_name0001" => :blank }, result.errors)
    assert_equal "ada@example.com", result.typed["f_mail0002"]
    assert_equal "  ", result.typed["f_name0001"]
  end

  test "501 characters in a short text and 5,001 in a long text are :too_long" do
    over = clean("f_name0001" => "x" * 501, "f_text0003" => "y" * 5_001)
    assert_equal({ "f_name0001" => :too_long, "f_text0003" => :too_long }, over.errors)
    assert_equal 501, over.typed["f_name0001"].length, "the text is kept for the redraw, not cut"

    assert_empty clean("f_name0001" => "x" * 500, "f_text0003" => "y" * 5_000).errors
  end

  test "an email with two addresses is :invalid" do
    assert_equal({ "f_mail0002" => :invalid }, clean("f_name0001" => "Ada", "f_mail0002" => "a@example.com, b@example.com").errors)
    assert_equal({ "f_mail0002" => :invalid }, clean("f_name0001" => "Ada", "f_mail0002" => "Ada <a@example.com>").errors)
    assert_empty clean("f_name0001" => "Ada", "f_mail0002" => "").errors, "an optional email may be left blank"
  end

  test "a choice key the field does not have is :inclusion" do
    assert_equal({ "f_pick0004" => :inclusion }, clean("f_name0001" => "Ada", "f_pick0004" => "c_zzzzzzzz").errors)
    assert_empty clean("f_name0001" => "Ada", "f_pick0004" => "c_aaaaaaaa").errors
  end

  test "a required checkbox unticked is :blank, ticked is Yes" do
    assert_equal({ "f_okay0005" => :blank }, Forms::Answers.clean(fields, { "f_name0001" => "Ada" }, locale: "en").errors)
    assert_equal({ "f_okay0005" => :blank }, Forms::Answers.clean(fields, { "f_name0001" => "Ada", "f_okay0005" => "0" }, locale: "en").errors)

    result = clean("f_name0001" => "Ada")
    assert_empty result.errors
    row = result.values.find { |value| value["key"] == "f_okay0005" }
    assert_equal [ true, "Yes", "checkbox" ], [ row["value"], row["display"], row["type"] ]
  end

  test "an answer for a key the form does not have is dropped" do
    result = clean("f_name0001" => "Ada", "f_other999" => "sneaky", "extra" => { "a" => 1 })

    assert_empty result.errors
    assert_equal fields.map(&:key), result.values.map { |value| value["key"] }
    assert_not_includes result.typed.keys, "f_other999"
    assert_not_includes result.values.to_s, "sneaky"
  end

  test "values carry the default-language label and display, whatever language the visitor sent in" do
    result = clean({ "f_name0001" => "Ada", "f_pick0004" => "c_aaaaaaaa" }, locale: "de")

    assert_empty result.errors
    name = result.values.find { |value| value["key"] == "f_name0001" }
    pick = result.values.find { |value| value["key"] == "f_pick0004" }
    assert_equal({ "key" => "f_name0001", "type" => "short_text", "label" => "Name", "value" => "Ada", "display" => "Ada" }, name)
    assert_equal({ "key" => "f_pick0004", "type" => "choice", "label" => "Topic", "value" => "c_aaaaaaaa", "display" => "Press" }, pick)
  end

  test "an unanswered optional field is stored with no value and an empty display, and a list or hash sent for a field is no answer" do
    result = clean("f_name0001" => "Ada", "f_text0003" => [ "x" ], "f_mail0002" => { "a" => "b" })

    assert_empty result.errors
    mail = result.values.find { |value| value["key"] == "f_mail0002" }
    assert_nil mail["value"]
    assert_equal "", mail["display"]
  end

  test "action controller parameters are read as they are" do
    params = ActionController::Parameters.new("f_name0001" => "Ada", "f_okay0005" => "1")

    assert_empty Forms::Answers.clean(fields, params, locale: "en").errors
  end

  test "an optional checkbox left unticked is stored as false and reads No, so a declined consent is not an absent one" do
    optional = Forms::Field.from_h("key" => "f_news0006", "type" => "checkbox", "label" => { "en" => "Newsletter" })
    result = Forms::Answers.clean([ optional ], {}, locale: "en")

    assert_empty result.errors
    assert_equal [ false, "No" ], result.values.first.values_at("value", "display")
    ticked = Forms::Answers.clean([ optional ], { "f_news0006" => "1" }, locale: "en")
    assert_equal [ true, "Yes" ], ticked.values.first.values_at("value", "display")
  end

  test "a choice label with markup is stored as the text it is" do
    markup = Forms::Field.from_h("key" => "f_pick0007", "type" => "choice", "label" => { "en" => "<b>Topic</b>" },
      "settings" => { "choices" => [ { "key" => "c_aaaaaaaa", "label" => { "en" => "<i>Press</i>" } } ] })
    row = Forms::Answers.clean([ markup ], { "f_pick0007" => "c_aaaaaaaa" }, locale: "en").values.first

    assert_equal [ "<b>Topic</b>", "<i>Press</i>" ], row.values_at("label", "display")
  end
end
