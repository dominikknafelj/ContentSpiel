require "test_helper"

# Settings › Post types (docs/reference/settings-languages-ai.md): the card
# saves with the bar, is `settings.manage`'s, and counts the viewer's kept
# readable posts in one statement.
class Admin::SettingsPostTypesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @site = site_settings(:default)
  end

  def save(types)
    patch "/cs-studio/settings", params: { site_setting: { content_types: types }, base_updated_at: @site.reload.updated_at.iso8601(6) }
  end

  def user_holding(*keys)
    user = users(:editor_branch)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    user
  end

  test "the card saves the switch with the save bar and needs settings.manage" do
    get "/cs-studio/settings"
    assert_select "form#settings-form #settings-post_types-card input.cs-toggle[name='site_setting[content_types][]']", 3

    save([ "", "blog", "resume_entry" ])

    assert_redirected_to "/cs-studio/settings"
    assert_equal %w[blog resume_entry], @site.reload.content_types

    languages_only = user_holding("languages.manage")
    sign_in_as(languages_only)
    get "/cs-studio/settings"
    assert_select "#settings-post_types-card", 0
    save([ "", "blog" ])
    assert_response :forbidden
    assert_equal %w[blog resume_entry], @site.reload.content_types
  end

  test "unticking every type answers 422 with the error on the card" do
    save([ "" ])

    assert_response :unprocessable_entity
    assert_select "#settings-post_types-card [data-post-types-errors]", text: /Keep at least one post type switched on\./
    assert_select "[data-error-summary], .admin-error-summary", text: /Keep at least one post type switched on\./
    assert_equal %w[blog resume_entry now_update], @site.reload.content_types
    assert_select "#settings-post_types-card [data-field-name=content_types][data-save-bar-changed=saved]"
    assert_select "#settings-post_types-card input.cs-toggle[checked]", 0
  end

  test "the counts are the viewer's readable kept posts, in one statement" do
    create_post(title: "One")
    create_post(title: "Two")
    create_post(title: "Role", content_type: "resume_entry")
    create_post(title: "Gone").update!(trashed_at: Time.current)

    get "/cs-studio/settings"
    assert_select "[data-post-type=blog] [data-post-count]", text: "2 posts"
    assert_select "[data-post-type=resume_entry] [data-post-count]", text: "1 post"
    assert_select "[data-post-type=now_update] [data-post-count]", 0

    counting = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      counting << payload[:sql] if payload[:sql].match?(/FROM "posts"/) && payload[:sql].include?("COUNT") && payload[:sql].include?(%("content_type"))
    end
    get "/cs-studio/settings"
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_equal 1, counting.size, counting.join("\n")
  end

  test "a viewer's counts leave out the posts their read grant does not reach" do
    create_post(title: "One")
    create_post(title: "Role", content_type: "resume_entry")
    create_post(title: "Role two", content_type: "resume_entry")
    group = access_control_groups(:branch_editors)
    user = users(:editor_branch)
    AccessControl::Grant.create!(group: group, permission: "settings.manage", scope: {})
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => [ "resume_entry" ] })
    AccessControl::Membership.create!(user: user, group: group) unless user.groups.exists?(group.id)
    sign_in_as(user)

    get "/cs-studio/settings"

    assert_select "[data-post-type=resume_entry] [data-post-count]", text: "2 posts"
    assert_select "[data-post-type=blog] [data-post-count]", 0
  end
end
