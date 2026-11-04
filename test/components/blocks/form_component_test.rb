require "test_helper"

# `Blocks::FormComponent` (forms plan, Task 7; design.md 4): an editor's
# form drawn by the theme, which posts to the form's own endpoint
# (`FormSendsController`) and is sent in place by `form-send`.
class Blocks::FormComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  def form_block(form = forms(:contact), page: root_page)
    page.content_blocks.create!(block_type: "form", position: page.content_blocks.count, settings: { "form_id" => form&.id&.to_s }.compact)
  end

  def draw(block, page: root_page) = render_inline(Blocks::FormComponent.new(block: block, page: page))

  def component(block, page: root_page) = Blocks::FormComponent.new(block: block, page: page)

  test "a form draws its fields, the hidden locale, page and drawn token, and the honeypot hidden from people and screen readers" do
    form = forms(:contact)
    block = form_block(form)
    freeze_time do
      draw(block)

      assert_selector "form.content-block.content-block--form[method=post][action='/forms/#{form.id}'][data-controller='form-send'][data-turbo='false']"
      assert_selector "form input[name='answers[f_name0001]'][type=text]#form-#{block.id}-f_name0001[required]"
      assert_selector "form input[name='answers[f_mail0001]'][type=email]"
      assert_selector "form textarea[name='answers[f_text0001]']"
      assert_selector "input[type=hidden][name=locale][value=en]", visible: :all
      assert_selector "input[type=hidden][name=page_id][value='#{root_page.id}']", visible: :all
      drawn = page.find("input[type=hidden][name=drawn]", visible: :all).value
      assert_equal Forms::Drawn.token(form), drawn, "the draw token is the draw's, signed for this form"

      honeypot = page.find("input[name=website]", visible: :all)
      assert_equal "-1", honeypot[:tabindex]
      assert_equal "off", honeypot[:autocomplete]
      assert_selector "div[hidden][aria-hidden=true] input[name=website]", visible: :all
      assert_selector "button[type=submit]", text: "Send"
      assert_selector "[role=alert][tabindex='-1'][hidden][data-form-send-target=summary]", visible: :all
      assert_selector "[role=status][tabindex='-1'][hidden][data-form-send-target=done]", text: "Thank you, we'll be in touch.", visible: :all
      # Every field's error element is drawn, empty and hidden, for the
      # script to fill (R15), and the control names it only once it holds a
      # message.
      %w[f_name0001 f_mail0001 f_text0001].each do |key|
        assert_selector "p#form-#{block.id}-#{key}-error[hidden]", text: "", visible: :all
      end
      assert_no_selector "[aria-describedby*='-error']"
      assert_selector "#form-#{block.id}-f_mail0001[aria-describedby='form-#{block.id}-f_mail0001-help']"
    end
  end

  test "the script's values are the server's words and every field's ids" do
    form = forms(:newsletter)
    block = form_block(form)
    draw(block)

    element = page.find("form[data-controller=form-send]")
    assert_equal "Sending…", element["data-form-send-sending-value"]
    assert_equal I18n.t("public.forms.network"), element["data-form-send-network-value"]
    fields = JSON.parse(element["data-form-send-fields-value"])
    assert_equal({ "error" => "form-#{block.id}-f_topic002-error", "target" => "form-#{block.id}-f_topic002-c_news0001" }, fields.fetch("f_topic002"),
      "a radio group's link goes to its first radio")
    assert_equal({ "error" => "form-#{block.id}-f_mail0002-error", "target" => "form-#{block.id}-f_mail0002" }, fields.fetch("f_mail0002"))
    assert_equal %w[f_mail0002 f_topic002 f_okay0002], fields.keys
  end

  test "required is said in words in the label" do
    draw(form_block(forms(:newsletter)))

    assert_selector "label[for$='-f_mail0002'] .form-field__required", text: "required"
    assert_no_selector "legend .form-field__required", text: "required"
    assert_selector "label[for$='-f_okay0002'] .form-field__required", text: "required"
    assert_no_selector "legend", text: "*"
  end

  test "a missing form, a trashed one and a form with no field draw nothing" do
    assert_not component(form_block(nil)).render?, "no form chosen"

    gone = root_page.content_blocks.create!(block_type: "form", position: 9, settings: { "form_id" => "999999" })
    assert_not component(gone).render?, "a stored id no form has"

    trashed = forms(:newsletter)
    block = form_block(trashed)
    trashed.update_columns(trashed_at: Time.current) # version: none (a test's row)
    assert_not component(block).render?, "a form in the trash"

    empty = forms(:contact)
    empty.update_columns(fields: []) # version: none (a test's row)
    assert_not component(form_block(empty)).render?, "a form with no field"
    draw(form_block(empty))
    assert_no_selector "form"
  end

  test "labels fall back to the default language and the submit label to Send" do
    form = forms(:newsletter)
    form.update_columns(submit_label: {}, thank_you: {}) # version: none (a test's row)
    block = form_block(form)

    I18n.with_locale(:de) { draw(block) }

    assert_selector "label", text: "Email address"
    assert_selector "button[type=submit]", text: "Send"
    assert_selector "[data-form-send-target=done]", text: "Thank you. Your answers have been sent.", visible: :all
    assert_selector "input[type=hidden][name=locale][value=de]", visible: :all

    form.update_columns(submit_label: { "en" => "Subscribe", "de" => "Abonnieren" }) # version: none (a test's row)
    I18n.with_locale(:de) { draw(block) }
    assert_selector "button[type=submit]", text: "Abonnieren"
  end

  test "a name, a label and a help line that look like markup are text" do
    form = forms(:contact)
    fields = form.read_attribute(:fields).deep_dup
    fields[0]["label"] = { "en" => "<b>Name</b>" }
    fields[1]["help"] = { "en" => "<img src=x onerror=alert(1)>" }
    form.update_columns(name: "<script>alert(1)</script>", fields: fields, thank_you: { "en" => "<i>Thanks</i>" }) # version: none (a test's row)
    block = form_block(form)
    draw(block)

    assert_no_selector "script", visible: :all
    assert_no_selector "img", visible: :all
    assert_no_selector "label b"
    assert_no_selector "[data-form-send-target=done] i", visible: :all
    assert_selector "label", text: "<b>Name</b>"
    assert_selector ".form-field__help", text: "<img src=x onerror=alert(1)>"
    assert_equal "<script>alert(1)</script>", component(block).send(:form_name), "the name is the editor's, not a visitor's: the default template draws it nowhere"
    assert_not_includes rendered_content, "<script>"
  end

  test "two Form blocks of one form on one page have distinct field ids and error links" do
    form = forms(:newsletter)
    one = form_block(form)
    two = form_block(form)
    html = [ one, two ].map { |block| draw(block).to_html }.join
    document = Nokogiri::HTML5.fragment(html)

    ids = document.css("[id]").map { |node| node["id"] }
    assert_equal ids.uniq, ids, "no id is drawn twice"
    fors = document.css("label[for]").map { |node| node["for"] }
    assert fors.all? { |id| ids.include?(id) }, "every label names a control of its own form"
    targets = document.css("form").map { |node| JSON.parse(node["data-form-send-fields-value"]).values.flat_map(&:values) }
    assert_empty targets[0] & targets[1], "the error links of the two forms go to their own fields"
    targets.flatten.each { |id| assert_includes ids, id }
  end

  test "string answers its six words and nothing else" do
    block = form_block
    subject = component(block)
    draw(block)

    assert_equal %i[required choose sending sent error_summary network], Blocks::FormComponent::STRINGS
    assert_equal [ "required", "Choose", "Sending…", "Thank you. Your answers have been sent." ], %i[required choose sending sent].map { |key| subject.send(:string, key) }
    assert_equal "Please correct 2 answers.", subject.send(:string, :error_summary, count: 2)
    assert_equal I18n.t("public.forms.network"), subject.send(:string, "network"), "a key written as a String is the same key"
    I18n.with_locale(:de) { assert_equal "required", subject.send(:string, :required), "English where the language has no words" }

    error = assert_raises(ArgumentError) { subject.send(:string, :gone) }
    assert_includes error.message, ":required, :choose, :sending, :sent, :error_summary, :network"

    Blocks::FormComponent.instance_variable_set(:@unknown_strings, nil)
    with_singleton_override(Rails, :env, -> { ActiveSupport::EnvironmentInquirer.new("production") }) do
      assert_equal "", subject.send(:string, :gone), "in production no word, never a sentence of I18n's"
    end
  end

  test "without encryption keys the form says it can't take answers, and nothing in it can be typed or sent" do
    block = form_block
    without_encryption_keys { draw(block) }

    assert_selector "p.form-unavailable", text: "This form can't take answers at the moment. Please try again later."
    assert_selector "fieldset[disabled] input[name='answers[f_name0001]']"
    assert_selector "fieldset[disabled] button[type=submit]"

    draw(block)
    assert_no_selector ".form-unavailable"
    assert_no_selector "fieldset[disabled]"
    assert_nil component(block).send(:unavailable)
  end
end
