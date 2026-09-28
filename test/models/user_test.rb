require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email address is required and unique" do
    User.create!(email_address: "taken@example.com", password: "password123")

    assert_not User.new(email_address: "", password: "password123").valid?
    assert_not User.new(email_address: "TAKEN@example.com", password: "password123").valid?
  end

  test "the last user can't be destroyed" do
    users(:two).destroy!
    last = users(:one)

    assert_not last.destroy
    assert_includes last.errors.full_messages, "The last user can't be deleted"
    assert User.exists?(last.id)
  end

  test "a user can be destroyed when another remains" do
    assert users(:two).destroy
    assert_not User.exists?(users(:two).id)
  end
end
