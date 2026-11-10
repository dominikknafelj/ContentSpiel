require "test_helper"

class Admin::TokensScreen::CreateStepComponentTest < ViewComponent::TestCase
  setup do
    @groups = [ access_control_groups(:admin), access_control_groups(:read_only) ]
  end

  test "a required Name, a Group select whose options carry their description, and Create token" do
    render_inline Admin::TokensScreen::CreateStepComponent.new(groups: @groups, form_url: "/cs-studio/api_tokens", selected_id: @groups.last.id)

    assert_selector "h2.text-h2", text: "1 · Create a token"
    assert_selector "form[action='/cs-studio/api_tokens'][data-turbo='false']"
    assert_selector "input#token-name[name=name][required][placeholder='claude-desktop'][maxlength='60']"
    assert_selector "select[name=group_id] option", count: 2
    assert_selector "select[name=group_id] option[selected]", text: @groups.last.name
    assert_selector "option[data-description='#{@groups.first.description}']"
    assert_selector "#token-group-description", text: @groups.last.description.to_s
    assert_button "Create token"
    assert_no_selector "#api-token-value"
  end

  test "errors print under their own field and the typed name is kept" do
    render_inline Admin::TokensScreen::CreateStepComponent.new(
      groups: @groups, form_url: "/x", name: "claude-desktop",
      name_errors: [ "Name is already the name of one of this user's active tokens" ], group_errors: [ "Choose a group for the token" ]
    )

    assert_selector "input#token-name[value='claude-desktop'][aria-invalid=true][aria-describedby='token-name-errors']"
    assert_selector "#token-name-errors", text: /already the name/
    assert_selector "#token-group-errors", text: "Choose a group for the token"
    assert_selector "select#group_id[aria-describedby='token-group-description token-group-errors']"
  end

  test "a refused name draws the shared invalid edge and its message" do
    render_inline Admin::TokensScreen::CreateStepComponent.new(
      groups: @groups, form_url: "/x", name: "", name_errors: [ "Name can't be blank" ]
    )

    assert_selector "div.admin-field > input#token-name[aria-invalid=true][aria-describedby='token-name-errors']"
    assert_selector "div.admin-field > div#token-name-errors > p", text: "Name can't be blank"
    assert_equal Admin::TokensScreen::CreateStepComponent::NAME_ERROR_ID, "token-name-errors"
    # The Group field is a field too, with its slot empty.
    assert_selector "div.admin-field > select#group_id:not([aria-invalid])"
    assert_selector "div.admin-field > div#token-group-errors", visible: :all
    assert_no_selector "#token-group-errors > p"
    assert_no_selector "[class*='border-danger']"
  end

  test "the reveal is a warn notice holding the token's copy box, a secret target, and nothing else holds the token" do
    token = "a" * 64
    render_inline Admin::TokensScreen::CreateStepComponent.new(groups: @groups, form_url: "/x", raw_token: token)

    notice = page.find("div[role=alert]", text: "Copy this token now. It won't be shown again.")
    assert_includes notice[:class].split, "bg-warn-tint"
    assert notice.has_selector?("div[data-controller='admin--ui--clipboard'] pre#api-token-value[data-admin--ui--clipboard-target=source][data-admin--tokens--reveal-target=secret]",
      exact_text: token), "the notice holds the token's copy box, a secret target"
    assert notice.has_selector?("button[aria-label='Copy token'][data-action='click->admin--ui--clipboard#copy']", exact_text: "Copy")
    assert_equal 1, rendered_content.scan(token).size, "the token is written once, as the copy box's text"
    assert_no_selector "[data-admin--tokens--reveal-target=status]", visible: :all
    assert_no_selector "[data-action*='admin--tokens--reveal']"
  end
end
