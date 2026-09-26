require "test_helper"

# Exercised directly, like RegenerateApiTokenActionTest: Avo's action
# dispatch is Avo's own machinery; the resource index smoke test in
# AvoAccessTest covers the wiring.
class CreateStarterPagesActionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "creates the starter pages in the site's default language" do
    SiteSetting.instance.update!(default_locale: "es")
    action = Avo::Actions::CreateStarterPages.new(user: @user)

    action.handle(current_user: @user)

    assert StarterContent.added?(locale: "es")
    assert_equal "Starter pages are ready.", action.response[:messages].first[:body]
  end

  test "running it again creates nothing new" do
    Avo::Actions::CreateStarterPages.new(user: @user).handle(current_user: @user)

    assert_no_difference [ "Page.count", "Post.count" ] do
      Avo::Actions::CreateStarterPages.new(user: @user).handle(current_user: @user)
    end
  end
end
