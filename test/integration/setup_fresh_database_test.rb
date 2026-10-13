require "test_helper"
require_relative "../support/schema_loaded_database"

# The setup wizard on a database as a schema load leaves it: no group, no
# user, no settings row (`SchemaLoadedDatabase`). That is the database of a
# first production start, and it had no built-in groups: the token step
# raised `ActiveRecord::RecordNotFound` (a 404) and the Groups screen was
# empty afterwards.
class SetupFreshDatabaseTest < ActionDispatch::IntegrationTest
  include SchemaLoadedDatabase

  setup { empty_as_after_a_schema_load }

  test "the wizard makes the built-in groups before its first write: the token step issues an Admin token and the Groups screen lists the four" do
    verify_setup_token
    assert_equal 0, AccessControl::Group.count, "the token step, which anyone may post to, writes nothing"

    create_setup_admin
    assert_redirected_to setup_step_path("site")
    assert_equal [ "Admin", "Author", "Editor", "Read only" ], AccessControl::Group.where(built_in: true).order(:name).pluck(:name)
    events = Audit::Event.where(action: "group.created")
    assert_equal [ "setup" ], events.pluck(:channel).uniq
    assert_equal 4, events.count

    assert_difference "ApiToken.count", 1 do
      patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    end
    assert_response :success
    token = ApiToken.authenticate(css_select("#mcp-token").first.text.strip)
    assert_equal "Admin", token.group.name
    assert_predicate token.group, :built_in?

    patch setup_step_path("review")
    assert_redirected_to "/cs-studio"

    get admin_groups_path
    assert_response :success
    [ "Admin", "Author", "Editor", "Read only" ].each { |name| assert_includes response.body, name }
  end

  test "a wizard resumed on a site whose first account was made before the groups were: the next step makes them" do
    verify_setup_token
    create_setup_admin
    ApiToken.delete_all
    AccessControl::Grant.delete_all
    AccessControl::Group.delete_all

    assert_difference "AccessControl::Group.count", 4 do
      patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    end
    assert_response :success
    assert_equal User.find_by!(email_address: "owner@example.com").id, Audit::Event.where(action: "group.created").order(:id).last.user_id
  end

  # The one way the group can still be absent: whoever is signed in may not
  # make groups. A person who is no owner, on a site whose setup was never
  # finished.
  test "with the Admin group missing and nobody allowed to make it, the token step says what is missing: 422, never a 404, and no token" do
    verify_setup_token
    create_setup_admin
    ApiToken.delete_all
    AccessControl::Grant.delete_all
    AccessControl::Group.delete_all
    sign_in_as User.create!(email_address: "helper@example.com", password: "password12345")

    assert_no_difference [ "ApiToken.count", "AccessControl::Group.count" ] do
      patch setup_step_path("mcp_token"), params: { token_name: "claude-desktop" }
    end

    assert_response :unprocessable_entity
    assert_select "#token-name-error", text: /no "Admin" group.*bin\/rails db:seed.*skip this step/m
    assert_select "input[name=token_name][value=?]", "claude-desktop"
    assert_select "a[href=?]", setup_step_path("starter_content"), text: "Skip"
    assert_select "#mcp-token", count: 0
  end
end
