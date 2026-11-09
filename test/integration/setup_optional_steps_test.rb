require "test_helper"

class SetupOptionalStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the Mail step is optional and says so, and its Skip goes on to Languages" do
    get setup_step_path("mail")

    assert_response :success
    assert_select "h1 span.text-label.text-meta", text: "Optional"
    assert_select "a[href=?]", setup_step_path("languages"), text: "Skip for now"
  end

  PRIMARY = Admin::Ui::ButtonComponent.classes(:primary)
  TERTIARY = Admin::Ui::ButtonComponent.classes(:tertiary)

  def primaries(nodes = css_select("[class]")) = nodes.select { |node| node["class"].to_s.include?(PRIMARY) }

  # The primary, or the `button_to` form it stands in, ends its row.
  def last_in_row?(node)
    node = node.parent if node.parent.name == "form" && node.parent["class"].to_s.split.include?("button_to")
    node.next_element.nil?
  end

  def assert_one_primary_last(step)
    found = primaries
    assert_equal 1, found.size, "#{step}: #{found.map { |node| node.text.strip }.inspect}"
    assert last_in_row?(found.first), "#{step}: the primary is not last in its row"
    css_select("a").select { |link| link.text.strip.in?([ "Back", "Skip for now" ]) }.each do |link|
      assert_includes link["class"], TERTIARY, "#{step}: #{link.text.strip}"
    end
  end

  test "every step draws one primary, last in its row, its Back and Skip tertiary" do
    sample = Nokogiri::HTML5.fragment(ApplicationController.render(Admin::Ui::ButtonComponent.new(label: "Go"), layout: false) +
      ApplicationController.render(Admin::Ui::ButtonComponent.new(label: "Back", variant: :tertiary), layout: false))
    assert_equal [ "Go" ], primaries(sample.css("[class]")).map(&:text), "the matcher finds the primary and nothing else"

    %w[site mail languages mcp_token starter_content review].each do |step|
      get setup_step_path(step)
      assert_response :success
      assert_one_primary_last(step)
    end
    assert_select "a", text: "Back", minimum: 1
    assert_select "a", text: "Skip for now", count: 0

    get setup_step_path("starter_content")
    assert_equal "Add starter content", primaries.first.text.strip
    get setup_step_path("mcp_token")
    assert_equal "Generate token", primaries.first.text.strip
    get setup_step_path("review")
    assert_equal "Finish setup", primaries.first.text.strip

    patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    assert_one_primary_last("mcp_token_created")

    ApiToken.delete_all
    Session.delete_all
    User.delete_all
    reset!
    get setup_step_path("token")
    assert_one_primary_last("token")
    verify_setup_token
    %w[system_check admin].each do |step|
      get setup_step_path(step)
      assert_one_primary_last(step)
    end
    get setup_step_path("system_check")
    row = primaries.first.parent.element_children.map { |node| node.text.strip }
    assert_equal [ "Re-run checks", "Back", "Continue" ], row, "the step's own secondary first, then Back, the primary last"
  end

  test "the MCP token step can be skipped" do
    get setup_step_path("mcp_token")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("starter_content"), text: "Skip for now"
    assert_match(/Admin group/, response.body)
  end

  test "the token step asks for a required name" do
    get setup_step_path("mcp_token")

    assert_select "h1", text: /Connect an AI agent/
    assert_select "input[name=token_name][required]"
    assert_select "label", text: "Token name"
    assert_match(/Helps you recognise which assistant is using it\. The token acts as you; revoke it any time in Studio › AI assistant\./, response.body)
    assert_select "button", text: "Generate token"
  end

  test "a blank token name is refused with 422 and no token" do
    assert_no_difference "ApiToken.count" do
      patch setup_step_path("mcp_token"), params: { token_name: "  " }
    end

    assert_response :unprocessable_entity
    assert_select "#token-name-error", text: /Name can't be blank/
    assert_select "#mcp-token", count: 0

    assert_no_difference "ApiToken.count" do
      patch setup_step_path("mcp_token")
    end
    assert_response :unprocessable_entity
  end

  test "generating an MCP token shows it once, bound to the admin and the Admin group, and never in flash" do
    assert_difference "ApiToken.count", 1 do
      patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    end

    assert_response :success
    assert_select "p", text: /This is the only time the full token is shown\. Copy it into your agent's config now\./
    raw = css_select("#mcp-token").first.text.strip
    token = ApiToken.authenticate(raw)
    assert_equal "claude-desktop", token.name
    assert_equal User.find_by(email_address: "owner@example.com"), token.user
    assert_equal AccessControl::Seeds::ADMIN_NAME, token.group.name
    assert_empty flash.to_h
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not_includes session.to_hash.to_s, raw
  end

  test "the review step shows the token's name, or Skipped, and never the token" do
    get setup_step_path("review")
    assert_select "dt", text: "MCP token"
    assert_select "dd", text: "Skipped"

    patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    raw = css_select("#mcp-token").first.text.strip

    get setup_step_path("review")
    assert_select "dd", text: "claude-desktop (created)"
    assert_not_includes response.body, raw
    assert_not_includes session.to_hash.to_s, raw
  end

  test "the starter content step can be skipped" do
    get setup_step_path("starter_content")

    assert_response :success
    assert_select "a[href=?]", setup_step_path("review"), text: "Skip for now"
  end

  test "adding starter content creates the pages in the default language" do
    SiteSetting.instance.update!(default_locale: "de")

    patch setup_step_path("starter_content")

    assert_redirected_to setup_step_path("review")
    assert StarterContent.added?(locale: "de")
  end

  # The wizard takes the same locked, re-checked path as CS Studio
  # (`StarterContents::Add`), and a failure is a form error on the step,
  # never a 500.
  test "adding starter content twice doesn't duplicate anything" do
    patch setup_step_path("starter_content")

    assert_no_difference [ "Page.count", "Post.count" ] do
      patch setup_step_path("starter_content")
    end
    assert_redirected_to setup_step_path("review")
  end

  test "a starter content failure is shown on the step instead of a 500" do
    with_singleton_override(StarterContents::EnsureHome, :call, ->(**) { raise StarterContent::Error, "StarterContent: Slug has already been taken" }) do
      patch setup_step_path("starter_content")
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /couldn.t be added/
  end
end
