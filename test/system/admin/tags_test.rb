require "application_system_test_case"

# The Tags list in a real browser (round 3, Task 13): the inline rename, the
# post count that opens the filtered posts list, and the row menu's Merge and
# Delete dialogs -- one of each in the page, filled from the row that opened it.
class Admin::TagsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      create_post(title: "First", tags: [ "news" ])
      create_post(title: "Second", tags: [ "news", "studio" ])
      create_post(title: "Third", tags: [ "studio", "gear" ])
    end
    @news, @studio, @gear = %w[news studio gear].map { |name| Tag.find_by!(name: name) }
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  def row(tag) = "tr#tag_#{tag.id}"

  def open_row_menu(tag, item)
    find("#{row(tag)} button[aria-label^='Actions for']").click
    find("#{row(tag)} [role=menu] button", text: item).click
  end

  test "clicking a name renames it in place and saves" do
    field = find("#tag-#{@gear.id}-name")
    field.set("kit")

    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}/, wait: 8
    assert_eventually { @gear.reload.name == "kit" }
  end

  test "a duplicate name shows its error on the row and keeps the old name" do
    field = find("#tag-#{@gear.id}-name")
    field.set("news")

    assert_selector "#tag-#{@gear.id}-name-errors", text: "has already been taken", wait: 8
    assert_equal "gear", @gear.reload.name
  end

  test "the post count opens the posts list filtered by that tag" do
    find("#{row(@news)} a", text: "2 posts").click

    assert_current_path(/\/posts\?tag=news/)
    assert_selector "tbody th a", text: "First"
    assert_selector "tbody th a", text: "Second"
    assert_no_selector "tbody th a", text: "Third"
  end

  test "Merge into… picks a target, never offers the tag itself, and moves the posts" do
    open_row_menu(@news, "Merge into…")

    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “news” into…"
      assert_text "Its 2 posts get the chosen tag and “news” is deleted. This can't be undone."
      assert_button "Merge tags", disabled: true

      find("#merge-tag-into").send_keys("s")
      assert_selector "#merge-tag-into-listbox [role=option]", text: "studio"
      assert_no_selector "#merge-tag-into-listbox [role=option]", text: "news"
      find("#merge-tag-into-listbox [role=option]", text: "studio").click

      assert_selector "li[data-chip-value='studio']"
      assert_button "Merge tags", disabled: false
      click_button "Merge tags"
    end

    assert_selector "#toasts .admin-toast", text: "Merged “news” into “studio”", wait: 10
    assert_no_selector row(@news)
    assert_selector "#{row(@studio)} a", text: "3 posts"
    assert_not Tag.exists?(@news.id)
  end

  test "the one Merge dialog is refilled for each row, with nothing left from the last opening" do
    open_row_menu(@news, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      find("#merge-tag-into").send_keys("s")
      find("#merge-tag-into-listbox [role=option]", text: "studio").click
      assert_button "Merge tags", disabled: false
      click_button "Cancel"
    end
    assert_no_selector "dialog[open]"

    open_row_menu(@gear, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “gear” into…"
      assert_text "Its 1 post gets the chosen tag"
      assert_no_selector "li[data-chip-value]"
      assert_button "Merge tags", disabled: true
    end
    assert_selector "dialog#merge-tag-dialog", count: 1, visible: :all
  end

  test "Delete tag… asks first, says how many posts are affected, and removes the row" do
    open_row_menu(@gear, "Delete tag…")

    within("dialog#delete-tag-dialog[open]") do
      assert_selector "h2", text: "Delete “gear”?"
      assert_text "It is removed from 1 post. The posts themselves stay."
      click_button "Delete tag"
    end

    assert_selector "#toasts .admin-toast", text: "Deleted “gear”", wait: 10
    assert_no_selector row(@gear)
    assert_no_selector "dialog[open]"
    assert_not Tag.exists?(@gear.id)
  end

  # Final wave B (ledger C-M7): the row's data was written when the list was
  # rendered; the dialogs name the tag as it is called now.
  test "after an inline rename the dialogs name the tag by its new name, and the picker excludes it" do
    find("#tag-#{@gear.id}-name").set("kit")
    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( TO SITE)? \d{2}:\d{2}/, wait: 8

    open_row_menu(@gear, "Delete tag…")
    within("dialog#delete-tag-dialog[open]") do
      assert_selector "h2", text: "Delete “kit”?"
      click_button "Cancel"
    end

    open_row_menu(@gear, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “kit” into…"
      find("#merge-tag-into").send_keys("k")
      assert_no_selector "#merge-tag-into-listbox [role=option]", text: "kit", wait: 1
    end
  end

  # Task 13 m4: a refusal has no body to render; the dialog stayed open over a
  # button that did nothing.
  test "a delete the server refuses closes the dialog and says so" do
    open_row_menu(@gear, "Delete tag…")
    assert_selector "dialog#delete-tag-dialog[open]"
    @gear.destroy!
    within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }

    assert_no_selector "dialog[open]"
    assert_selector "#toasts [role=alert]", text: "The tag wasn't deleted. Reload the list and try again."
  end

  # Task 13 m6 and m7.
  test "after a delete the focus is on a neighbouring row, and deleting the last tag shows the empty state" do
    rows = page.all("table.admin-tags-table tbody tr").map { |tr| tr[:id] }
    first = Tag.find(rows.first.delete_prefix("tag_"))
    open_row_menu(first, "Delete tag…")
    within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }
    assert_no_selector row(first)
    assert_eventually(message: "focus fell to the body") { page.evaluate_script("document.activeElement.id") == "tag-#{rows.second.delete_prefix('tag_')}-name" }

    rows.drop(1).each do |id|
      tag = Tag.find(id.delete_prefix("tag_"))
      open_row_menu(tag, "Delete tag…")
      within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }
      assert_no_selector row(tag)
    end
    assert_text "No tags yet"
    assert_no_selector "table.admin-tags-table"
  end
end
