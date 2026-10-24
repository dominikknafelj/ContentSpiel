require "application_system_test_case"

# The editor's field details (design pass round 2, Task 10): soft SEO counters
# that never block a save, the hero alt override's Reset, and a boolean toggle
# that autosaves.
class Admin::EditorFieldsSystemTest < ApplicationSystemTestCase
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "an empty slug says the slug the title will give as soon as the editor opens, and follows the title" do
    post = create_post(title: "Notes on Rails", published: false)
    post.update_columns(slug: {}) # version: none (a test's own setup: a draft whose slug was never filled)
    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers

    slug = find("[data-admin--editor--slug-preview-target=slug]")
    assert_equal "", slug.value
    assert_equal "notes-on-rails", slug[:placeholder]

    find("[data-admin--editor--slug-preview-target=title]").set("Hello, World")
    assert_eventually(message: "the placeholder never followed the title") { slug[:placeholder] == "hello-world" }
    assert_writes_settled
  end

  test "a 70-character meta title shows the long counter and still saves" do
    about = create_page(title: "About")
    visit "/cs-studio/pages/#{about.id}"
    await_admin_controllers

    find("summary", text: "SEO · META TITLE, META DESCRIPTION").click
    assert_text "0 / 60"
    fill_in "Meta title", with: "x" * 70

    assert_text "70 / 60 · long"
    assert_eventually(message: "the long meta title was never saved") { about.reload.meta_title(locale: "en").to_s.length == 70 }
  end

  # Review C, M14: not a live region rewritten per keystroke; the crossing of
  # the limit is the one thing said.
  test "the counter announces only the crossing of the limit" do
    about = create_page(title: "About")
    visit "/cs-studio/pages/#{about.id}"
    await_admin_controllers

    find("summary", text: "SEO · META TITLE, META DESCRIPTION").click
    announcement = "[data-admin--ui--char-count-target=announcement]"
    assert_no_selector "[data-admin--ui--char-count-target=output][aria-live]", visible: :all
    fill_in "Meta title", with: "x" * 59
    assert_selector announcement, exact_text: "", visible: :all
    fill_in "Meta title", with: "x" * 61
    assert_selector announcement, text: "Over the recommended length: 61 of 60.", visible: :all
    fill_in "Meta title", with: "x" * 62
    assert_selector announcement, text: "Over the recommended length: 61 of 60.", visible: :all
    fill_in "Meta title", with: "x" * 10
    assert_selector announcement, text: "Back within the recommended length.", visible: :all
  end

  test "Reset empties an overridden hero alt, shows the library alt as the placeholder and saves the cleared value" do
    asset = create_media_asset
    asset.update!(alt: "A dog on a beach")
    landing = Pages::Save.call(attributes: { parent: root_page, page_type: :landing, published: true, hero_media_asset_id: asset.id },
      translations: { Locales.default => { title: "Landing", hero_alt: "My own alt" } }).record

    visit "/cs-studio/pages/#{landing.id}"
    await_admin_controllers

    assert_field "page-hero_alt", with: "My own alt"
    assert_text "A dog on a beach"
    click_button "Reset"

    assert_field "page-hero_alt", with: ""
    assert_equal "A dog on a beach", find_field("page-hero_alt")[:placeholder]
    assert_no_button "Reset"
    assert_eventually(message: "the cleared hero alt was never saved") { landing.reload.hero_alt(locale: "en").blank? }
  end

  test "toggling a boolean saves it" do
    with_test_types do
      ContentTypes.register "test/flagged" do |t|
        t.label "Flagged"
        t.list_component Posts::BlogListComponent
        t.detail_component Posts::DetailComponent
        t.field :featured, :boolean
      end
      post_record = create_post(title: "Launch", content_type: "test/flagged")

      visit "/cs-studio/posts/#{post_record.id}"
      await_admin_controllers

      assert_selector "[data-fields-group-title]", text: /flagged fields/i
      find("input.cs-toggle[role=switch]").click
      assert_eventually(message: "the toggle was never saved") { post_record.reload.fields.featured == true }

      find("input.cs-toggle[role=switch]").click
      assert_eventually(message: "the toggle was never cleared") { post_record.reload.fields.featured == false }
    end
  end
end
