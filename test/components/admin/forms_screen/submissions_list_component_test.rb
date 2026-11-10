require "test_helper"

# A form's submissions: a failed delivery is a system's state, said in a warn
# state chip, never a badge and never red; the language is a neutral badge;
# the table scrolls sideways inside its card, and a row opens from any cell.
class Admin::FormsScreen::SubmissionsListComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def t(key, **values) = I18n.t("admin.components.forms_screen.submissions_list.#{key}", **values)

  def submission(locale: "en") = Forms::Submission.create!(form: forms(:contact), locale: locale, answers: [])

  def render_list(submissions)
    render_inline Admin::FormsScreen::SubmissionsListComponent.new(form: forms(:contact), submissions: submissions,
      pagination: Pagination.new(page: 1, per_page: 50, total: submissions.size), total: submissions.size, page_url: ->(number) { "/submissions?page=#{number}" })
  end

  def row(record) = page.find("tr##{ActionView::RecordIdentifier.dom_id(record)}")

  test "a submission whose delivery failed says Not delivered in a warn state chip, and its language is a neutral badge" do
    failed = submission(locale: "de")
    failed.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)).record_failed!(key: "login", line: nil, at: Time.current)
    delivered = submission
    delivered.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)).record_sent!(at: Time.current)
    render_list([ failed, delivered ])

    assert_equal "Not delivered", t("not_delivered")
    assert row(failed).has_selector?(".admin-state-chip[data-state-tone=warn]", text: t("not_delivered")), "the failed row says so in a warn state chip"
    assert row(failed).has_no_selector?("[class~='bg-warn-tint']:not(.admin-state-chip)"), "no warn badge beside it"
    assert row(delivered).has_no_selector?(".admin-state-chip"), "a delivered row says nothing"
    assert_no_match(/(?<![\w-])(?:bg|text|border)-danger/, page.find("table tbody").native.to_html, "a failed delivery is never red")

    badge = row(failed).find("td:nth-child(3) span", text: "DE")
    assert_equal Admin::Ui::BadgeComponent::TONES.fetch(:neutral).split.sort, (badge[:class].split & Admin::Ui::BadgeComponent::TONES.fetch(:neutral).split).sort

    assert_selector ".admin-table-scroll--x table.admin-form-submissions-table"
    assert_selector "p.text-small.text-meta", text: t("not_kept", days: Forms::UNDELIVERED_DAYS)
    # The row's stretched link stands in its last cell, absolute against the
    # row: the first cell is sticky, so a link stretched from it would cover
    # that cell alone. It takes no Tab stop and says nothing (the time link is both).
    assert row(failed).has_selector?("td:first-child a[href$='/submissions/#{failed.id}']:not([tabindex])")
    assert row(failed).has_selector?("td:last-child a.absolute.inset-0[tabindex='-1'][aria-hidden=true][href$='/submissions/#{failed.id}']", visible: :all)
  end
end
