require "test_helper"

# The builder: one row per field with its
# label, its type's options and its key in a hidden input; destinations
# whose secrets are never drawn; and every editor's text as text.
class Admin::FormsScreen::BuilderComponentTest < ViewComponent::TestCase
  module Deliverer
    def self.deliver(_delivery, final_attempt:) = nil
  end

  setup { Current.actor = users(:one) }

  def render_builder(form, locale: "en")
    render_inline Admin::FormsScreen::BuilderComponent.new(form: form, draft: Admin::FormsScreen::Draft.from_form(form),
      locale: locale, placements: Forms::Placements.new(form, viewer: users(:one)))
  end

  def t(key, **values) = I18n.t("admin.components.forms_screen.#{key}", **values)

  test "every field row has a label, its type's options and its key in a hidden input" do
    form = forms(:newsletter)
    render_builder(form)

    form.fields.each do |field|
      assert_selector "[data-admin--forms--builder-target=row][data-key='#{field.key}']" do
        assert_selector "input[type=hidden][name='form[fields][#{field.key}][key]'][value='#{field.key}']", visible: :all
        assert_selector "input[type=hidden][name='form[fields][#{field.key}][type]'][value='#{field.type}']", visible: :all
        assert_selector "input[name='form[fields][#{field.key}][label][en]'][value='#{field.label["en"]}']"
        assert_selector "label", text: t("field_row.label")
        assert_selector "input[name='form[fields][#{field.key}][help][en]']"
        assert_selector "input[type=checkbox][name='form[fields][#{field.key}][required]']"
      end
    end
    topic = form.fields.find { |field| field.type == "choice" }
    assert_selector "[data-key='#{topic.key}'] input[type=radio][name='form[fields][#{topic.key}][display]'][value=radios][checked]", visible: :all
    topic.choices.each do |choice|
      assert_selector "[data-key='#{topic.key}'] input[name='form[fields][#{topic.key}][choices][#{choice.key}][label][en]'][value='#{choice.label["en"]}']"
      assert_selector "input[type=hidden][name='form[fields][#{topic.key}][choices][#{choice.key}][key]'][value='#{choice.key}']", visible: :all
    end
    assert_selector "[data-key='#{form.fields.first.key}'] input[type=radio]", count: 0, visible: :all
    assert_selector "input[type=hidden][name='form[field_order]'][value='#{form.fields.map(&:key).join(" ")}']", visible: :all
    # One template per registered type, in the registry's order, each a button of the picker.
    Forms::FieldTypes.all.each do |type|
      assert_selector "template[data-type='#{type.name}']", visible: :all
      assert_selector "button[data-admin--forms--builder-type-param='#{type.name}']"
    end
  end

  test "a secret of a destination is never drawn, only Set or not" do
    Forms::DestinationTypes.register("acme/crm", label: "Acme CRM", deliverer: Deliverer) do |d|
      d.field :list, :string, required: true
      d.secret :api_key
    end
    result = Forms::Save.call(Forms::Form.new, attributes: { name: "Signup", keep_submissions: false },
      fields: [ { type: "email", label: { "en" => "Email" } } ],
      destinations: [ { kind: "acme/crm", settings: { list: "subscribers" }, secrets: { api_key: "s3cret-value" } } ])
    assert result.ok?, result.errors.to_sentence
    form = result.record.reload
    destination = form.destinations.first

    render_builder(form)
    assert_no_text "s3cret-value"
    assert_not_includes page.native.to_html, "s3cret-value"
    assert_not_includes page.native.to_html, destination.secrets["api_key"], "nor its ciphertext"
    assert_selector "input[type=password][name$='[secrets][api_key]']:not([value])"
    assert_text t("destinations.set_on", date: I18n.l(destination.secrets_saved_at.in_time_zone(Current.site.effective_time_zone).to_date, format: :"admin.short_with_year"))
    assert_selector "input[type=hidden][name$='[id]'][value='#{destination.id}']", visible: :all

    fresh = Forms::Save.call(Forms::Form.new, attributes: { name: "Other", keep_submissions: false },
      fields: [], destinations: [ { kind: "acme/crm", settings: { list: "x" }, secrets: {} } ]).record
    render_builder(fresh.reload)
    assert_text t("destinations.not_set")
  ensure
    Rails.application.reloader.prepare!
  end

  test "a label that looks like markup is text" do
    markup = "<img src=x onerror=alert(1)>"
    form = forms(:contact)
    fields = form.fields.map(&:to_h)
    fields.first["label"] = { "en" => markup }
    fields.first["help"] = { "en" => "<b>bold</b>" }
    form.update_columns(fields: fields, name: "<script>x</script>") # version: none (a test's row)

    render_builder(form.reload)
    assert_selector "img", count: 0
    assert_selector "script", count: 0, visible: :all
    assert_selector "b", count: 0
    assert_selector "input[value='#{markup}']"
    assert_selector "button", text: markup
  end
end
