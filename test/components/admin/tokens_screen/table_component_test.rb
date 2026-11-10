require "test_helper"

class Admin::TokensScreen::TableComponentTest < ViewComponent::TestCase
  def tokens_table(tokens) = render_inline(Admin::TokensScreen::TableComponent.new(tokens: tokens))

  test "columns, a last-used IP on a second line, and a revoke dialog naming the token" do
    token, = ApiToken.generate!(users(:one), name: "claude-desktop")
    token.record_usage!("203.0.113.5")
    revoked, = ApiToken.generate!(users(:one), name: "old")
    revoked.revoke!

    tokens_table ApiToken.where(id: [ token.id, revoked.id ]).includes(:user, :group).order(:id)

    assert_equal %w[Name Acts\ as Group Created Last\ used Status Actions], page.all("th").map { |th| th.text.strip }
    assert_selector "tr#api_token_#{token.id}", text: /claude-desktop.*Active/m
    assert_selector "tr#api_token_#{token.id} span.block.text-small.text-meta", text: "203.0.113.5"
    assert_selector "tr#api_token_#{token.id}", text: "Revoke…"
    assert_selector "dialog#revoke-api-token-#{token.id}", text: "Revoke “claude-desktop”?", visible: :all
    assert_selector "dialog#revoke-api-token-#{token.id} button", text: "Revoke token", visible: :all
    assert_selector "tr#api_token_#{revoked.id}", text: /old.*Revoked/m
    assert_selector "tr#api_token_#{revoked.id} button", count: 0
    assert_text "Never"
  end

  test "a token's state is a state chip: Active ok, Revoked off with its time, and a revoked row has no opacity" do
    active, = ApiToken.generate!(users(:one), name: "claude-desktop")
    revoked, = ApiToken.generate!(users(:one), name: "old")
    revoked.revoke!

    tokens_table ApiToken.where(id: [ active.id, revoked.id ]).includes(:user, :group).order(:id)

    assert_selector "tr#api_token_#{active.id} span.admin-state-chip[data-state-tone=ok]", exact_text: "Active"
    assert_selector "tr#api_token_#{revoked.id} span.admin-state-chip[data-state-tone=off]", exact_text: "Revoked"
    assert_selector "tr#api_token_#{revoked.id} span.admin-state-chip + span.text-meta > time[datetime='#{revoked.reload.revoked_at.in_time_zone.iso8601}']"
    assert_no_selector "[class*='opacity-']"
    # A revoked row's words are meta; an active row's are not.
    page.all("tr#api_token_#{revoked.id} > td").first(5).each { |cell| assert_includes cell[:class].split, "text-meta", cell.text }
    page.all("tr#api_token_#{active.id} > td").first(5).each { |cell| assert_not_includes cell[:class].split, "text-meta", cell.text }

    revoke = page.find("tr#api_token_#{active.id} button", text: "Revoke…")
    assert_equal Admin::Ui::ButtonComponent.classes(:danger_text, size: :small).split.sort, revoke[:class].split.sort
  end

  test "the table scrolls inside its card, its Name column sticky, and the empty line is a key" do
    ApiToken.generate!(users(:one), name: "claude-desktop")
    tokens_table ApiToken.includes(:user, :group)

    assert_selector "section > h2.text-h2", text: "Tokens"
    assert_selector "section > div.admin-table-scroll--x.rounded-card > table.admin-card-table"
    # The Name column sticks (`.admin-table-scroll--x`) because no row is one link.
    assert_no_selector ".admin-row-link"

    tokens_table ApiToken.none
    assert_no_selector "table"
    assert_equal "No tokens yet.", I18n.t("admin.components.tokens_screen.table.empty.title")
    assert_equal "Create a token to connect an assistant.", I18n.t("admin.components.tokens_screen.table.empty.description")
    assert_text "No tokens yet."
    assert_text "Create a token to connect an assistant."
  end
end
