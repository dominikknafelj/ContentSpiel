require "test_helper"

# Final fix wave (Important 3): the founding owner is created through
# `Users::Save` on the `:setup` channel (one `user.created` event), and
# every later step writes as that owner -- its events carry their user_id,
# not a nil actor.
class SetupAttributionTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
  end

  test "the founding owner is created through the audited path" do
    create_setup_admin
    owner = User.find_by!(email_address: "owner@example.com")

    event = Audit::Event.find_by!(action: "user.created", subject: owner)
    assert_equal "setup", event.channel
    assert_nil event.actor
    assert event.snapshot["owner"]
    assert_not_includes event.snapshot.keys, "password_digest"
  end

  test "every step after the admin account is attributed to the owner" do
    create_setup_admin
    owner = User.find_by!(email_address: "owner@example.com")
    since = Audit::Event.maximum(:id).to_i

    patch setup_step_path("site"), params: { site_setting: { title: "Owner's site" } }
    assert_redirected_to setup_step_path("languages")
    patch setup_step_path("languages"), params: { site_setting: { default_locale: "en", extra_locales: [ "de" ] } }
    assert_redirected_to setup_step_path("mcp_token")
    patch setup_step_path("mcp_token")
    assert_response :success
    patch setup_step_path("starter_content")
    assert_redirected_to setup_step_path("review")
    patch setup_step_path("review")
    assert_redirected_to "/cs-studio"

    events = Audit::Event.where("id > ?", since).order(:id)
    assert_includes events.map(&:action), "settings.updated"
    assert_includes events.map(&:action), "token.issued"
    assert_includes events.map(&:action), "page.created"
    events.each do |event|
      assert_equal owner.id, event.user_id, "#{event.action} wasn't attributed to the owner"
      assert_equal owner, event.actor
      assert_equal "setup", event.channel
    end
  end
end
