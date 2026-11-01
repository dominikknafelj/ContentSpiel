require "test_helper"

class Admin::Fields::LinkFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "a text input with inputmode url and the stored address, and no pattern or maxlength" do
    field = Field.new(name: "target", type: :link, options: {})
    render_inline Admin::Fields::LinkField.new(field:, form_name: "block[settings]", value: "/about?x=1", locale: "en")

    assert_selector "input[type=text][inputmode=url][name='block[settings][target]'][value='/about?x=1']"
    assert_no_selector "input[pattern]"
    assert_no_selector "input[maxlength]"
  end

  def link_field(value, name: "block[settings]")
    field = Field.new(name: "target", type: :link, options: {})
    render_inline Admin::Fields::LinkField.new(field:, form_name: name, value:, locale: "en")
  end

  test "a typed address is the input as it was, and the search beside it has no name, so it is never sent" do
    link_field "/about"

    assert_selector "input[type=text][name='block[settings][target]'][value='/about']:not([hidden])"
    assert_selector "input[type=text]:not([name])[aria-label]", count: 1
    assert_no_selector "[data-admin--ui--link-target-target=chip]:not([hidden])"
    assert_selector "[data-controller='admin--ui--link-target'][data-admin--ui--link-target-url-value*='link_targets']"
  end

  test "a chosen target reads as its title with a way to clear it, and its reference is only the field's value" do
    target = create_page(title: "Our services")
    link_field "cs:page/#{target.id}"

    assert_selector "[data-admin--ui--link-target-target=title]", text: "Our services"
    assert_selector "button[data-action*='admin--ui--link-target#clear']"
    assert_selector "input[name='block[settings][target]'][value='cs:page/#{target.id}'][hidden]", visible: :all
    assert_no_text "cs:page"
    assert_selector "[data-admin--ui--link-target-target=note][hidden]", visible: :all
  end

  test "a target that isn't public yet says so quietly" do
    target = create_page(title: "A draft", published: false)
    link_field "cs:page/#{target.id}"

    assert_selector "[data-admin--ui--link-target-target=title]", text: "A draft"
    assert_selector "[data-admin--ui--link-target-target=note]:not([hidden])", text: I18n.t("admin.components.fields.link_field.not_public")
  end

  test "a target outside the viewer's read scope and a deleted one read the same, and neither its title nor its reference is text" do
    target = create_page(title: "Hidden from them")
    as(users(:editor_branch)) do
      link_field "cs:page/#{target.id}"
      assert_no_text "Hidden from them"
      assert_no_text "cs:page"
      unreadable = page.find("[data-admin--ui--link-target-target=title]").text
      assert_equal I18n.t("admin.components.fields.link_field.unavailable"), unreadable

      link_field "cs:page/999999"
      assert_equal unreadable, page.find("[data-admin--ui--link-target-target=title]").text
    end
    assert_equal I18n.t("admin.components.fields.link_field.unavailable"), as(users(:editor_branch)) { Admin::Fields::LinkField.display(nil, "cs:page/#{target.id}") }
  end

  test "where it can't be edited a reference reads as its title or the neutral words, and an address as itself" do
    target = create_page(title: "Our services")
    assert_equal "Our services", Admin::Fields::LinkField.display(nil, "cs:page/#{target.id}")
    assert_equal I18n.t("admin.components.fields.link_field.unavailable"), Admin::Fields::LinkField.display(nil, "cs:page/999999")
    assert_equal "/about", Admin::Fields::LinkField.display(nil, "/about")
  end

  test "in a held form the value stays, nothing can be typed or pressed and no action survives" do
    target = create_page(title: "Our services")
    link_field "cs:page/#{target.id}"
    held = Admin::EditorScreen::HeldFields.call(rendered_content)
    fragment = Nokogiri::HTML5.fragment(held)

    assert_equal "cs:page/#{target.id}", fragment.at_css("input[name='block[settings][target]']")["value"]
    assert fragment.at_css("input[name='block[settings][target]']").key?("readonly")
    assert fragment.at_css("input:not([name])").key?("readonly")
    assert fragment.at_css("button").key?("disabled")
    assert_empty fragment.css("[data-action]").flat_map { |node| node["data-action"].split }
    assert_includes fragment.text, "Our services"
  end
end
