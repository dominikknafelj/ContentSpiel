require "test_helper"

class Admin::UsersScreen::InviteDialogComponentTest < ViewComponent::TestCase
  def dialog(invite: nil, errors: [], resend_invitation: nil)
    with_request_url("/cs-studio/users") do
      render_inline Admin::UsersScreen::InviteDialogComponent.new(groups: AccessControl::Group.order(:name).to_a, assignable_ids: [],
        invite: invite, errors: errors, resend_invitation: resend_invitation)
    end
  end

  test "a refused address draws the shared invalid edge and its message, with Resend inside it" do
    invited = open_invitation("dana@example.com")
    invite = Invitation.new(email_address: "dana@example.com")
    invite.errors.add(:email_address, "This address is already invited.")
    dialog(invite: invite, errors: invite.errors.full_messages, resend_invitation: invited)

    assert_selector "div.admin-field > input#invite_email_address[aria-invalid=true][aria-describedby='invite_email_address-errors']", visible: :all
    assert_selector "div.admin-field > div#invite_email_address-errors > p", text: "This address is already invited.", visible: :all
    assert_selector "#invite_email_address-errors button[type=submit][form=invite-person-resend]", text: "Resend", visible: :all
    resend = page.find("#invite_email_address-errors button", visible: :all)
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split.sort, resend["class"].split.sort
    assert_selector "div.admin-field > input#invite_name", visible: :all
    assert_no_selector "[class*='border-danger']", visible: :all
    assert_no_selector "[role=alert].bg-danger-tint", visible: :all
  end

  test "a refusal about no field is the danger notice at the top" do
    dialog(errors: [ "Invites need mail." ])

    assert_selector "div[role=alert]", text: "Invites need mail.", visible: :all
    notice = page.find("div[role=alert]", text: "Invites need mail.", visible: :all)
    assert_empty Admin::Ui::NoticeComponent.classes(:danger, size: :compact).split - notice["class"].split
    assert_no_selector "div#invite_email_address-errors > p", visible: :all
  end

  test "an untouched dialog shows no error and no notice" do
    dialog

    assert_no_selector "[role=alert]", visible: :all
    assert_no_selector "input[aria-invalid]", visible: :all
  end
end
