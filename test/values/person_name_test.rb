require "test_helper"

class PersonNameTest < ActiveSupport::TestCase
  Someone = Struct.new(:name, :email_address)

  test "a person is their name, and without one the part of the address before the at sign" do
    assert_equal "Dana Weiss", PersonName.of(Someone.new("Dana Weiss", "dana@example.com"))
    assert_equal "dana", PersonName.of(Someone.new(nil, "dana@example.com"))
    assert_equal "dana", PersonName.of(Someone.new("  ", "dana@example.com"))
  end

  test "an address with nothing before the at sign, and one without an at sign, are said as they are" do
    assert_equal "@example.com", PersonName.of(Someone.new(nil, "@example.com"))
    assert_equal "dana", PersonName.of(Someone.new(nil, "dana"))
  end

  test "a real user's display name is not this rule" do
    user = users(:two).tap { |each| each.update!(name: nil) }

    assert_equal "two", PersonName.of(user)
    assert_equal user.email_address, user.display_name
  end

  test "initials are the first character of the first two words as they were written; one word is one letter" do
    assert_equal "DW", PersonName.initials("Dana Weiss")
    assert_equal "dv", PersonName.initials("dana van weiss")
    assert_equal "d", PersonName.initials("dana")
    assert_equal "d", PersonName.initials("d")
  end

  test "initials of odd names: digits, an emoji, an accent, a leading at sign, nothing" do
    assert_equal "7o", PersonName.initials("7 of 9")
    assert_equal "👩‍🚀d", PersonName.initials("👩‍🚀 dana")
    assert_equal "e\u0301l", PersonName.initials("e\u0301lodie laurent")
    assert_equal "d", PersonName.initials("@dana")
    assert_equal "@", PersonName.initials("@")
    assert_equal "DW", PersonName.initials("(Dana) \"Weiss\"")
    assert_equal "", PersonName.initials("  ")
    assert_equal "", PersonName.initials(nil)
  end
end
