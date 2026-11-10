require "test_helper"

# The forms list: a failed delivery is a system's state, said in words in a
# warn state chip beside the count, never a badge and never red; the table
# scrolls sideways inside its card.
class Admin::FormsScreen::ListComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def render_list(forms)
    render_inline Admin::FormsScreen::ListComponent.new(forms: forms, pagination: Pagination.new(page: 1, per_page: 50, total: forms.size),
      page_url: ->(number) { "/forms?page=#{number}" }, mail_settings: MailSettings.current, keys: true, viewer: users(:one))
  end

  def fail_delivery(form)
    submission = Forms::Submission.create!(form: form, locale: "en", answers: [])
    submission.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)).record_failed!(key: "unreachable", line: nil, at: Time.current)
  end

  test "a form with failed deliveries says 2 not delivered in a warn state chip, never a badge or red" do
    form = forms(:contact)
    2.times { fail_delivery(form) }
    render_list([ form ])

    words = I18n.t("admin.components.forms_screen.list.not_delivered", count: 2)
    assert_equal "2 not delivered", words
    cell = page.find("##{ActionView::RecordIdentifier.dom_id(form)} td:nth-child(3)")
    assert cell.has_selector?(".admin-state-chip[data-state-tone=warn]", text: words), "the count is followed by the warn state chip"
    assert cell.has_no_selector?("[class~='bg-warn-tint']:not(.admin-state-chip)"), "no warn badge beside it"
    assert_no_match(/(?<![\w-])(?:bg|text|border)-danger/, cell.native.to_html, "a failed delivery is never red")
    assert_selector ".admin-table-scroll--x table.admin-forms-table"
  end
end
