require "test_helper"

# A live page's address, changed through its own confirmed form (drafts spec D7).
class Admin::EditorScreen::SlugDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_dialog(page, locale: "en")
    as_owner { render_inline Admin::EditorScreen::SlugDialogComponent.new(page: page, locale: locale) }
  end

  test "the dialog says the address changes at once and its form goes through the write queue's hold" do
    page = create_page(title: "Pricing")
    render_dialog(page)

    id = Admin::EditorScreen::SlugDialogComponent.dialog_id_for(page)
    assert_selector "dialog##{id}[data-dialog-width=form_narrow]", visible: :all
    assert_selector "##{id}-title", text: "Change this page’s address", visible: :all
    assert_selector "label[for='#{id}-slug']", text: "Last part of the address", visible: :all
    assert_selector "input##{id}-slug[name=slug][value='pricing']", visible: :all
    assert_selector "dialog##{id}", text: "The page moves to the new address at once, and the old address redirects to it. This does not wait for “Publish changes…”.", visible: :all
    assert_selector "form##{id}-form[method=post][action='/cs-studio/pages/#{page.id}/slug'][data-turbo-frame='_top'][data-controller='admin--saving--queue-hold'][data-action='submit->admin--saving--queue-hold#submit']", visible: :all
    assert_selector "form##{id}-form input[name=_method][value=patch]", visible: :all
    assert_selector "dialog##{id} footer button.bg-accent[form='#{id}-form']", text: "Change address", visible: :all
    assert_selector "dialog##{id} footer button", text: "Cancel", visible: :all
  end

  test "the field holds the slug of the language being edited" do
    page = create_page(title: "Pricing")
    Mobility.with_locale(:de) { page.update!(slug: "preise") }
    render_dialog(page.reload, locale: "de")

    assert_selector "input[name=slug][value='preise']", visible: :all
  end

  test "the homepage has no address to change, and a draft has no dialog" do
    render_dialog(root_page)
    assert_no_selector "dialog", visible: :all

    render_dialog(create_page(title: "Draft", published: false))
    assert_no_selector "dialog", visible: :all
  end
end
