require "application_system_test_case"

# Filters apply as they change (design pass spec §4): typing narrows the list
# without any button, focus stays in the search box across the reload, a
# select applies on choosing, and Clear brings everything back (and empties
# the search box -- the reason focus is restored by hand rather than with
# `data-turbo-permanent`, see `admin--auto-submit`).
class FiltersSystemTest < ApplicationSystemTestCase
  test "typing, choosing and clearing filter the posts list with no button" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    create_post(title: "Alpine notes")
    create_post(title: "Beach holiday", published: false)
    sign_in_via_form(users(:one))

    visit "/cs-studio/posts"
    await_admin_controllers
    assert_text "Alpine notes"
    assert_text "Beach holiday"
    assert_no_button "Filter"

    find_field("Title").click
    find_field("Title").send_keys("alp")
    assert_no_text "Beach holiday", wait: 5
    assert_text "Alpine notes"
    assert_equal "q", page.evaluate_script("document.activeElement.id"), "the search box keeps focus"
    assert_equal 3, page.evaluate_script("document.activeElement.selectionStart"), "and its caret"

    click_on "Clear"
    assert_text "Beach holiday", wait: 5
    assert_text "Alpine notes"
    assert_equal "", find_field("Title").value

    select "Draft", from: "Status"
    assert_no_text "Alpine notes", wait: 5
    assert_text "Beach holiday"
  end

  # A keyboard user stepping through a select's options submits on every
  # change; the reload must hand focus back to the select, or each arrow
  # press would throw them to the top of the page. The same holds for any
  # other control without a caret (a number or date field).
  test "a select filter keeps focus after it applies" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    create_post(title: "Alpine notes")
    create_post(title: "Beach holiday", published: false)
    sign_in_via_form(users(:one))

    visit "/cs-studio/posts"
    await_admin_controllers
    assert_text "Alpine notes"

    status = find_field("Status")
    status_id = status[:id]
    assert status_id.present?
    page.execute_script("document.getElementById(arguments[0]).focus()", status_id)
    select "Draft", from: "Status"
    assert_no_text "Alpine notes", wait: 5
    assert_text "Beach holiday"
    assert_equal status_id, page.evaluate_script("document.activeElement.id"), "the select keeps focus"
  end
end
