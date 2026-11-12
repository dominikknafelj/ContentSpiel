require "test_helper"

class Passkeys::PolicyTest < ActiveSupport::TestCase
  def policy(name)
    Current.site.update!(passkey_policy: name)
    Passkeys::Policy.current
  end

  def holder_of(key)
    group = AccessControl::Group.create!(name: "Holds #{key}")
    AccessControl::Grant.create!(group: group, permission: key, scope: {})
    user = User.create!(email_address: "#{key.tr(".", "-")}@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(group: group, user: user)
    user
  end

  test "owners_and_admins covers an owner and a holder of each admin key, and not an editor" do
    owners_and_admins = policy("owners_and_admins")

    assert owners_and_admins.covers?(users(:one))
    Passkeys::Policy::ADMIN_PERMISSIONS.each do |key|
      assert owners_and_admins.covers?(holder_of(key)), "a holder of #{key} is an admin"
    end
    assert_equal %w[users.manage groups.manage tokens.manage], Passkeys::Policy::ADMIN_PERMISSIONS
    assert_not owners_and_admins.covers?(holder_of("posts.edit"))
    assert_not owners_and_admins.covers?(users(:reader))
    assert owners_and_admins.covers_owners?
    assert_equal "owners_and_admins", owners_and_admins.name
  end

  test "everyone covers every person and nobody covers none" do
    everyone = policy("everyone")
    nobody = policy("nobody")

    [ users(:one), users(:two), users(:reader) ].each do |user|
      assert everyone.covers?(user)
      assert_not nobody.covers?(user)
    end
    assert everyone.covers_owners?
    assert_not nobody.covers_owners?
  end

  test "unset, the policy is the environment's default, and a site row need not be Current's" do
    Current.site.update!(passkey_policy: nil)

    assert_equal "nobody", Passkeys::Policy.current.name
    assert_equal "everyone", Passkeys::Policy.current(site: SiteSetting.new(passkey_policy: "everyone")).name
  end

  test "enrolment is due for a covered person with no passkey only" do
    everyone = policy("everyone")
    assert everyone.enrolment_due?(users(:reader))

    add_passkey(users(:reader), client: fake_authenticator)
    assert_not everyone.enrolment_due?(users(:reader))
    assert_not policy("nobody").enrolment_due?(users(:two))
  end

  test "uncovered_count counts covered people without a passkey" do
    owners_and_admins = policy("owners_and_admins")
    before = owners_and_admins.uncovered_count
    assert_operator before, :>=, 2 # the owner and the Admin group's member

    add_passkey(users(:two), client: fake_authenticator)
    add_passkey(users(:reader), client: fake_authenticator)
    assert_equal before - 1, owners_and_admins.uncovered_count

    holder_of("tokens.manage")
    assert_equal before, owners_and_admins.uncovered_count

    assert_equal User.where.missing(:passkeys).count, policy("everyone").uncovered_count
    assert_equal 0, policy("nobody").uncovered_count
  end
end
