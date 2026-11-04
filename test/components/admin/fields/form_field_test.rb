require "test_helper"

# The Form block's one field in CS Studio (forms plan, Task 7; spec
# decision 10): a select of every kept form by name, which placing a form
# needs nothing but the right to edit the page for.
class Admin::Fields::FormFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def field = Field.new(name: "form_id", type: :form, options: {})

  def draw(value) = render_inline(Admin::Fields::FormField.new(field: field, form_name: "block[settings]", value: value, locale: "en"))

  test "the select lists kept forms by name, and names a stored form that's gone" do
    contact, newsletter = forms(:contact), forms(:newsletter)
    Forms::Form.create!(name: "Archived", fields: []).update_columns(trashed_at: Time.current) # version: none (a test's row)

    draw(nil)
    assert_selector "select[name='block[settings][form_id]']"
    assert_equal [ "Choose a form", "Contact", "Newsletter" ], page.all("option").map(&:text), "kept forms by name, the trash's not offered"
    assert_selector "option[value='']", text: "Choose a form"
    assert_selector "option[value='#{newsletter.id}']", text: "Newsletter"
    assert_selector "option[selected]", count: 1, text: "Choose a form"

    draw(contact.id.to_s)
    assert_selector "option[selected][value='#{contact.id}']", text: "Contact"

    newsletter.update_columns(trashed_at: Time.current) # version: none (a test's row)
    draw(newsletter.id.to_s)
    assert_equal [ "A form that's gone", "Choose a form", "Contact" ], page.all("option").map(&:text)
    assert_selector "option[selected][value='#{newsletter.id}']", text: "A form that's gone"

    assert_equal "Contact", Admin::Fields::FormField.display(field, contact.id.to_s)
    assert_equal "A form that's gone", Admin::Fields::FormField.display(field, newsletter.id.to_s)
    assert_nil Admin::Fields::FormField.display(field, nil)
  end

  test "a form's name that looks like markup is text" do
    forms(:contact).update_columns(name: "<b>Contact</b>") # version: none (a test's row)
    draw(nil)

    assert_no_selector "option b"
    assert_selector "option", text: "<b>Contact</b>"
  end
end
