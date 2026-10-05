require "test_helper"

class Admin::TokensScreen::TableComponentTest < ViewComponent::TestCase
  test "columns, a last-used IP on a second line, and a revoke dialog naming the token" do
    token, = ApiToken.generate!(users(:one), name: "claude-desktop")
    token.record_usage!("203.0.113.5")
    revoked, = ApiToken.generate!(users(:one), name: "old")
    revoked.revoke!

    render_inline Admin::TokensScreen::TableComponent.new(tokens: ApiToken.where(id: [ token.id, revoked.id ]).includes(:user, :group).order(:id))

    assert_equal %w[Name Acts\ as Group Created Last\ used Status Actions], page.all("th").map { |th| th.text.strip }
    assert_selector "tr#api_token_#{token.id}", text: /claude-desktop.*Active/m
    assert_selector "tr#api_token_#{token.id} span.font-cs-mono", text: "203.0.113.5"
    assert_selector "tr#api_token_#{token.id}", text: "Revoke…"
    assert_selector "dialog#revoke-api-token-#{token.id}", text: "Revoke “claude-desktop”?", visible: :all
    assert_selector "tr#api_token_#{revoked.id}.opacity-60", text: /old.*Revoked/m
    assert_selector "tr#api_token_#{revoked.id} button", count: 0
    assert_text "Never"
  end

  test "an empty list is the empty state" do
    render_inline Admin::TokensScreen::TableComponent.new(tokens: ApiToken.none)

    assert_text "No tokens yet"
    assert_no_selector "table"
  end
end
