require "test_helper"

class Admin::Shell::AccountIdentityComponentTest < ViewComponent::TestCase
  test "names the user, then the email and role, under one id a stream can replace" do
    user = users(:one)
    user.update_columns(name: "Ada <b>Lovelace</b>")
    render_inline(Admin::Shell::AccountIdentityComponent.new(user: user))

    assert_selector "#account-identity span[title='Ada <b>Lovelace</b>']", text: "Ada <b>Lovelace</b>"
    assert_no_selector "#account-identity b"
    assert_selector "#account-identity span", text: "#{user.email_address} · Owner"
  end

  test "a user without a name shows the email once" do
    user = users(:one)
    user.update_columns(name: nil)
    render_inline(Admin::Shell::AccountIdentityComponent.new(user: user))

    assert_selector "#account-identity span", text: user.email_address, count: 1
    assert_selector "#account-identity span", text: /\AOwner\z/
  end

  # The handoff's decision 25: the block is a link to the account screen,
  # with the address parameters of the page it is drawn on.
  test "the block is a link to the account screen" do
    render_inline(Admin::Shell::AccountIdentityComponent.new(user: users(:one)))
    assert_selector "a#account-identity[href='/cs-studio/account/password']"

    render_inline(Admin::Shell::AccountIdentityComponent.new(user: users(:one), url_options: { locale: "de" }))
    assert_selector "a#account-identity[href='/cs-studio/account/password?locale=de']"
  end
end
