require "test_helper"

class Users::DestroyTest < ActiveSupport::TestCase
  test "deletes a user when another remains" do
    users(:one)
    result = Users::Destroy.call(users(:two), actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_not User.exists?(users(:two).id)
  end

  test "refuses to delete the last user" do
    users(:two).destroy!
    last = users(:one)

    result = Users::Destroy.call(last, actor: nil)

    assert_not result.ok?
    assert_equal [ "The last user can't be deleted" ], result.errors
    assert User.exists?(last.id)
  end
end
