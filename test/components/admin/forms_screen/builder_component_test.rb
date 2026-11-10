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

  test "the builder's cards are the shared card frame with the form chip, and no card draws its own head" do
    render_builder(forms(:newsletter))

    %w[form-card-form form-card-fields form-card-after form-destinations form-placements].each do |heading_id|
      card = "section.admin-settings-card[aria-labelledby='#{heading_id}'] > .admin-settings-card__head"
      assert_selector "#{card} h2##{heading_id}.text-h2"
      assert_selector "#{card} > span[aria-hidden=true].bg-ic-form-bg", count: 1
    end
    assert_selector "section.admin-settings-card", count: 5
    assert_selector "section.admin-settings-card > div.border-b", count: 0
    assert_not Admin::FormsScreen::BuilderComponent.const_defined?(:CARD_CLASS, false)
    assert_not Admin::FormsScreen::BuilderComponent.const_defined?(:CARD_HEAD_CLASS, false)
  end

  test "Add a field is a paper well titled in a label, its types secondary buttons, with no dashed edge" do
    render_builder(forms(:newsletter))

    well = "div.rounded-tile.bg-paper.p-3.admin-block-picker"
    assert_selector "#{well} > p.text-label.text-meta", text: t("builder.add_field")
    Forms::FieldTypes.all.each { |type| assert_selector "#{well} button", text: type.label }
    assert_equal "Add a field", t("builder.add_field")
    assert_selector ".border-dashed", count: 0
  end

  test "an invalid name is aria-invalid with the shared edge, never a danger border" do
    form = forms(:newsletter)
    render_inline Admin::FormsScreen::BuilderComponent.new(form: form, draft: Admin::FormsScreen::Draft.from_form(form), locale: "en",
      placements: Forms::Placements.new(form, viewer: users(:one)), errors: [ Forms::Save.sentence(:name_blank) ])

    assert_selector ".admin-field > input#form-name[aria-invalid=true]"
    assert_selector ".admin-field > #form-name-errors > p", text: Forms::Save.sentence(:name_blank)
    assert_no_match(/!border-danger/, page.native.to_html)
  end
end
