require "test_helper"

# The group editor's delete zone: the shared action zone, the neutral note
# of a built-in group, and the dialog's whole sentences.
class Admin::GroupsScreen::DeleteZoneComponentTest < ViewComponent::TestCase
  def zone(group, members: 2, tokens: [])
    with_request_url("/cs-studio/groups/#{group.id}/edit") do
      render_inline Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: members, tokens: tokens)
    end
  end

  def token(name, user)
    ApiToken.generate!(user, group: AccessControl::Group.find_by!(name: "Admin"), name: name)[0]
  end

  test "a custom group is the shared zone, with no pending lock" do
    zone(AccessControl::Group.create!(name: "Bots"))

    assert_selector "section.admin-action-zone.mt-6[data-zone=delete][aria-labelledby=delete-zone-title]:not([data-controller])"
    assert_selector "section[data-zone=delete] h2#delete-zone-title.text-h3", text: "Delete this group"
    assert_selector "section[data-zone=delete] > button.text-danger-ink", text: "Delete group…"
  end

  test "a group with 1 member and 12 tokens names 10 tokens and says 2 more, in whole sentences" do
    group = AccessControl::Group.create!(name: "Bots")
    tokens = Array.new(12) { |index| token("Bot #{index + 1}", users(:reader)) }
    zone(group, members: 1, tokens: tokens)

    assert_selector "section[data-zone=delete] p", exact_text: "1 member loses its permissions. 12 AI tokens are revoked."
    assert_selector "dialog p", exact_text: "Its 1 member loses these permissions, and its 12 AI tokens are revoked. Users themselves are not deleted.", visible: :all
    assert_selector "dialog li", count: Admin::GroupsScreen::DeleteZoneComponent::MAX_TOKENS_SHOWN, visible: :all
    assert_selector "dialog p", exact_text: "and 2 more", visible: :all
  end

  test "the dialog's sentence for no members with tokens, and for many members with one token" do
    group = AccessControl::Group.create!(name: "Bots")
    zone(group, members: 0, tokens: [ token("Deploy", users(:reader)) ])
    assert_selector "dialog p", exact_text: "It has no members, and its 1 AI token is revoked. Users themselves are not deleted.", visible: :all

    zone(group, members: 3, tokens: [ token("Sync", users(:reader)) ])
    assert_selector "dialog p", exact_text: "Its 3 members lose these permissions, and its 1 AI token is revoked. Users themselves are not deleted.", visible: :all

    zone(group, members: 0)
    assert_selector "dialog p", exact_text: "It has no members. Users themselves are not deleted.", visible: :all
    assert_selector "section[data-zone=delete] p", exact_text: "It has no members. It has no AI tokens."
  end

  # A language with a `few` category (CLDR's, under `I18n::Backend::Pluralization`)
  # is handed its `few` sentence for the members, not `one` or `other` picked by
  # comparing with 1. A throwaway backend loads the app's locale files, takes a
  # plural rule with `few` for 3 and a `few` branch of the sentence, and is put
  # back afterwards. The zone's `effect` has no `few` branch, so it takes
  # `other`, as Pluralization falls back.
  test "the members' sentence follows the locale's plural rule, a few category included" do
    backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Pluralization }.new
    backend.store_translations(:en, i18n: { plural: { rule: ->(count) { count == 1 ? :one : (2..4).cover?(count) ? :few : :other } } })
    backend.store_translations(:en, admin: { components: { groups_screen: { delete_zone: { dialog_body: { members_and_tokens: { few: {
      one: "Its %{members} members (few) lose these permissions, and its 1 AI token is revoked.",
      other: "Its %{members} members (few) lose these permissions, and its %{count} AI tokens are revoked."
    } } } } } } })
    original = I18n.backend
    I18n.backend = backend
    group = AccessControl::Group.create!(name: "Bots")

    zone(group, members: 3, tokens: [ token("Sync", users(:reader)) ])
    assert_selector "section[data-zone=delete] p", exact_text: "3 members lose its permissions. 1 AI token is revoked.", count: 1
    assert_selector "dialog p", exact_text: "Its 3 members (few) lose these permissions, and its 1 AI token is revoked.", visible: :all

    zone(group, members: 5, tokens: [ token("Deploy", users(:reader)) ])
    assert_selector "dialog p", text: "Its 5 members lose these permissions, and its 1 AI token is revoked.", visible: :all
  ensure
    I18n.backend = original if original
  end

  test "a custom group: the effect in words, a danger-text trigger, and the dialog with the solid danger confirm" do
    group = AccessControl::Group.create!(name: "Bots")
    zone(group, members: 2, tokens: [ token("Deploy", users(:reader)) ])

    assert_selector "h2", text: "Delete this group"
    assert_text "2 members lose its permissions. 1 AI token is revoked."
    assert_selector "button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='delete-group-#{group.id}']", text: "Delete group…"
    assert_selector "dialog#delete-group-#{group.id}", visible: :all do
      assert_selector "form[action='/cs-studio/groups/#{group.id}'] input[name=_method][value=delete]", visible: :all
    end
    assert_selector "dialog button[type=submit]", text: "Delete group", visible: :all
    assert_selector "dialog p", text: "Its 2 members lose these permissions, and its 1 AI token is revoked. Users themselves are not deleted.", visible: :all
    assert_selector "dialog li", text: "Deploy — reader@example.com", visible: :all
  end

  test "a built-in group says so in a neutral note in the zone's place" do
    zone(access_control_groups(:editor))

    note = page.find("div[data-zone=built_in][role=note]", text: "A built-in group can be changed but not deleted.")
    Admin::Ui::NoticeComponent.classes(:neutral).split.each { |utility| assert_includes note[:class].split, utility }
    assert_no_selector "section"
    assert_no_selector "button"
    assert_no_selector "dialog", visible: :all
  end

  test "the wording for one member, none and no tokens" do
    group = AccessControl::Group.create!(name: "Quiet")
    zone(group, members: 1)
    assert_text "1 member loses its permissions. It has no AI tokens."
    assert_selector "dialog p", text: "Its 1 member loses these permissions. Users themselves are not deleted.", visible: :all

    zone(group, members: 0)
    assert_text "It has no members. It has no AI tokens."
  end
end
