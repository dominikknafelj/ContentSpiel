require "test_helper"

class Admin::TokensScreen::CreateStepComponentTest < ViewComponent::TestCase
  setup do
    @groups = [ access_control_groups(:admin), access_control_groups(:read_only) ]
  end

  test "a required Name, a Group select whose options carry their description, and Create token" do
    render_inline Admin::TokensScreen::CreateStepComponent.new(groups: @groups, form_url: "/cs-studio/api_tokens", selected_id: @groups.last.id)

    assert_selector "h2", text: "1 · Create a token"
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

    assert_selector "input#token-name[value='claude-desktop'][aria-invalid=true][aria-describedby='token-name-error']"
    assert_selector "#token-name-error", text: /already the name/
    assert_selector "#token-group-error", text: "Choose a group for the token"
  end

  test "with a raw token it shows the warn box, the token and Copy token" do
    render_inline Admin::TokensScreen::CreateStepComponent.new(groups: @groups, form_url: "/x", raw_token: "a" * 64)

    assert_text "Copy this token now. It won't be shown again."
    assert_selector "pre#api-token-value[data-admin--tokens--reveal-target=secret]", text: "a" * 64
    assert_selector "button[data-admin--tokens--reveal-source-param=api-token-value]", text: "Copy token"
  end
end
