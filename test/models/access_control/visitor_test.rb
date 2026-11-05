require "test_helper"

# The one new actor: a visitor on the public site,
# `AccessControl::VISITOR`, may send a form and do nothing else, anywhere.
# This is the bent rule "a nil or unknown actor on :public is denied
# everything", now "everything but forms.submit for the visitor"; this test
# is its first guard (every registered key on every channel), and
# test/lib/visitor_actor_test.rb, which keeps the actor to the one
# controller that may act as it, is its second.
class AccessControl::VisitorTest < ActiveSupport::TestCase
  CHANNELS = [ :public, "public", :admin, :mcp, :setup, :console, :system, nil, "" ].freeze

  # What a key is checked on: a subject key needs a record of its subject.
  def record_for(permission)
    case permission.subject&.name
    when "Page" then @page ||= root_page
    when "Post" then @post ||= create_post(title: "A post")
    when nil then nil
    else flunk "no record for #{permission.key}'s subject #{permission.subject}"
    end
  end

  test "a visitor is allowed forms.submit on :public and nothing else: every registered key on every channel" do
    AccessControl::Permissions.all.each do |permission|
      CHANNELS.each do |channel|
        allowed = AccessControl.allowed?(AccessControl::VISITOR, permission.key, record_for(permission), channel: channel)
        expected = permission.key == "forms.submit" && channel.to_s == "public"
        assert_equal expected, allowed, "#{permission.key} on #{channel.inspect}"
        assert_not AccessControl.holds?(AccessControl::VISITOR, permission.key, channel: channel) unless expected
      end
    end
  end

  test "the visitor is one value with nothing in it, and no record" do
    assert_kind_of AccessControl::Visitor, AccessControl::VISITOR
    assert_predicate AccessControl::VISITOR, :frozen?
    assert_empty AccessControl::Visitor.members
    assert_not AccessControl.trusted?(AccessControl::VISITOR, :public)
    assert_not AccessControl.trusted?(AccessControl::VISITOR, :system), "a visitor is no trusted code path, on any channel"
  end

  test "nil on :public is still denied forms.submit" do
    assert_not AccessControl.allowed?(nil, "forms.submit", forms(:contact), channel: :public)
    assert_not AccessControl.allowed?(nil, "pages.read", root_page, channel: :public)
  end

  test "a user, an owner's token and a group can't be given forms.submit" do
    reader = users(:reader)
    assert_not AccessControl.allowed?(reader, "forms.submit", forms(:contact), channel: :public)
    assert_not AccessControl.allowed?(reader, "forms.submit", forms(:contact), channel: :admin)

    token = ApiToken.generate!(users(:one), group: access_control_groups(:admin)).first
    assert_not AccessControl.allowed?(token, "forms.submit", forms(:contact), channel: :mcp), "an owner's token acts within its group, which can't hold it"
    assert_not AccessControl.allowed?(token, "forms.submit", forms(:contact), channel: :public)

    grant = AccessControl::Grant.new(group: access_control_groups(:admin), permission: "forms.submit", scope: {})
    assert_not grant.valid?
    assert_not AccessControl.can_grant?(users(:one), "forms.submit")
  end
end
