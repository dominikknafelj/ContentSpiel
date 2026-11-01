require "application_system_test_case"

# Choosing a page or a post for a Card's link (#145), by keyboard alone, in the
# browser: what the combobox does, what is saved through the form's autosave,
# what a reload shows and what a held card leaves of it.
class Admin::CardLinkTargetSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Cards")
    @target = create_page(title: "Our services")
    @draft = create_page(title: "Secret plans", published: false)
    saved = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "card", settings: { "title" => "Card words" } })
    assert saved.ok?, saved.errors.to_sentence
    @card = saved.record
  end

  def form = find("#content_block_#{@card.id}")

  def stored_link = @card.reload.settings["link"]

  test "a target is chosen by keyboard, saved, kept over a reload, and cleared back to an address, with the search itself sending nothing" do
    sign_in_via_form(users(:one))
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    stamp = @card.reload.updated_at

    within(form) do
      search = find("input[aria-label='Or search pages and posts…']")
      search.send_keys("Our serv")
      assert_selector "[role=option]", text: "Our services"
      assert_equal stamp, @card.reload.updated_at, "a title being searched for is not saved"

      search.send_keys(:down, :enter)
      assert_selector "[data-admin--ui--link-target-target=title]", text: "Our services"
      assert_no_selector "[role=option]"
      assert_no_selector "input[aria-label='Or search pages and posts…']"
      assert_equal "Clear", evaluate_script("document.activeElement.textContent.trim()"), "the focus lands on the way to undo it"
    end
    assert_writes_settled
    assert_eventually(wait: 5, message: "the reference is stored") { stored_link == "cs:page/#{@target.id}" }
    assert_no_text "cs:page"

    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    within(form) do
      assert_selector "[data-admin--ui--link-target-target=title]", text: "Our services"
      assert_no_selector "[data-admin--ui--link-target-target=note]"
      assert_no_selector "input[name='block[settings][link]']"
      find("[data-admin--ui--link-target-target=clear]").send_keys(:enter)
      assert_selector "input[name='block[settings][link]']"
      assert_equal "block[settings][link]", evaluate_script("document.activeElement.name"), "the focus lands in the address field"
    end
    assert_writes_settled
    assert_eventually(wait: 5, message: "cleared") { stored_link.nil? }

    within(form) { find("input[name='block[settings][link]']").send_keys("/about", :tab) }
    assert_writes_settled
    assert_eventually(wait: 5, message: "a typed address is saved as before") { stored_link == "/about" }
  end

  test "Enter with no row chosen submits nothing, and a target that is not public says so quietly" do
    sign_in_via_form(users(:one))
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    url = current_url

    within(form) do
      search = find("input[aria-label='Or search pages and posts…']")
      search.send_keys("Secret", :enter)
      assert_selector "[role=option]", text: "Secret plans"
      assert_no_selector "[data-admin--ui--link-target-target=title]"
      search.send_keys(:down, :enter)
      assert_selector "[data-admin--ui--link-target-target=note]", text: I18n.t("admin.components.fields.link_field.not_public")
    end
    assert_equal url, current_url
    assert_writes_settled
    assert_eventually(wait: 5, message: "stored") { stored_link == "cs:page/#{@draft.id}" }
  end

  test "a card someone else holds shows its target read-only: no search, no Clear, nothing to press" do
    ContentBlocks::Save.call(@card, attributes: { settings: { "title" => "Card words", "link" => "cs:page/#{@target.id}" } })
    dana = users(:two)
    Editing::Reservation.claim(subject: @card, record: @page, user: dana, tab: "tab-bbbbbbbb", now: Time.current)
    sign_in_via_form(users(:one))
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live

    within(form) do
      assert_selector "[data-admin--ui--link-target-target=title]", text: "Our services"
      assert_no_button "Clear"
      assert_no_selector "input[aria-label='Or search pages and posts…']"
      assert_no_selector "[data-admin--ui--link-target-target=clear]"
    end
    assert_no_text "cs:page"
  end
end
