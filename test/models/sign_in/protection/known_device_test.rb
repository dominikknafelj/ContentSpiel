require "test_helper"

# A browser that has signed in before, as the sign-in cookie holds it: a
# random id and the accounts' keys, trusted in nothing it is read back from.
class SignIn::Protection::KnownDeviceTest < ActiveSupport::TestCase
  test "a new device knows no account; remembering one knows it, by an HMAC and never the email" do
    device = SignIn::Protection::KnownDevice.new
    assert_match(/\A\h{32}\z/, device.id)
    assert_not device.knows?("ann@example.org")

    remembered = device.remember("ann@example.org")
    assert remembered.knows?("ann@example.org")
    assert_not remembered.knows?("bea@example.org")
    assert_equal device.id, remembered.id
    assert_not_includes remembered.to_h.to_json, "ann"
    assert_equal remembered.to_h, SignIn::Protection::KnownDevice.read(JSON.parse(remembered.to_h.to_json)).to_h
  end

  test "it keeps the five latest accounts, the latest first" do
    device = (1..7).reduce(SignIn::Protection::KnownDevice.new) { |known, index| known.remember("person#{index}@example.org") }
    assert_equal 5, device.accounts.size
    assert device.knows?("person7@example.org")
    assert_not device.knows?("person2@example.org")

    again = device.remember("person4@example.org")
    assert_equal SignIn::Protection::KnownDevice.account_key("person4@example.org"), again.accounts.first
    assert_equal 5, again.accounts.size
  end

  test "anything but its own shape is a device that knows nothing" do
    key = SignIn::Protection::KnownDevice.account_key("ann@example.org")
    [ nil, "text", [], { "id" => "x", "accounts" => [ key ] }, { "id" => "a" * 32, "accounts" => key },
      { "id" => "a" * 32 } ].each do |junk|
      assert_empty SignIn::Protection::KnownDevice.read(junk).accounts, junk.inspect
    end
    assert_equal [ key ], SignIn::Protection::KnownDevice.read({ "id" => "a" * 32, "accounts" => [ key, "short", 7 ] }).accounts
  end
end
