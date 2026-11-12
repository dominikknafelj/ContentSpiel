require "test_helper"

class Passkeys::RenameTest < ActiveSupport::TestCase
  setup do
    @user = users(:reader)
    @passkey = add_passkey(@user, client: fake_authenticator, name: "MacBook")
  end

  def rename(name, actor: @user)
    as(actor) { Passkeys::Rename.call(@passkey, name: name) }
  end

  test "a person renames their own passkey, and the change is recorded with both names" do
    result = rename("  Work laptop ")

    assert result.ok?, result.errors.inspect
    assert_equal "Work laptop", @passkey.reload.name
    event = Audit::Event.find_by!(action: "passkey.renamed")
    assert_equal [ @passkey, @user ], [ event.subject, event.actor ]
    assert_equal({ "name" => [ "MacBook", "Work laptop" ] }, event.field_changes)
  end

  test "a blank name is the model's refusal and nothing is recorded" do
    result = rename(" ")

    assert_not result.ok?
    assert_equal [ "Give the passkey a name." ], result.errors
    assert_equal "MacBook", @passkey.reload.name
    assert_empty Audit::Event.all
  end

  test "the same name again writes and records nothing" do
    assert rename("MacBook").ok?
    assert_empty Audit::Event.all
  end

  test "another user's passkey is denied and nothing is written" do
    result = rename("Mine now", actor: users(:one))

    assert result.denied?
    assert_equal "MacBook", @passkey.reload.name
    assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
  end
end
