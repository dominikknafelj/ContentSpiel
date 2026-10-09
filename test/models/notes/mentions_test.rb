require "test_helper"

class Notes::MentionsTest < ActiveSupport::TestCase
  test "ids are the token's numbers, once each, in order" do
    assert_equal [ 7, 3 ], Notes::Mentions.ids("@[7] and @[3] and @[7]")
    assert_equal [], Notes::Mentions.ids("mail me @home or @[abc] or @ [4]")
    assert_equal [], Notes::Mentions.ids(nil)
  end

  # A bigint holds 19 digits; a longer number is nobody's id, and one that
  # reached `mentioned_user_ids` would raise on save instead of being refused.
  test "a number too long to be an id is not a mention" do
    assert_equal [], Notes::Mentions.ids("@[99999999999999999999]")
    assert_equal [ 999_999_999_999_999_999 ], Notes::Mentions.ids("@[999999999999999999]")
  end

  test "tokenize turns the names the picker inserted into tokens, the longest name first" do
    names = { "Dana" => 4, "Dana Smith" => 9 }

    assert_equal "Ask @[9], not @[4].", Notes::Mentions.tokenize("Ask @Dana Smith, not @Dana.", names)
  end

  test "tokenize ignores a name whose id is not a number and a text with no such name" do
    assert_equal "Hi @Dana", Notes::Mentions.tokenize("Hi @Dana", { "Dana" => "4; DROP" })
    assert_equal "Hi there", Notes::Mentions.tokenize("Hi there", { "Dana" => 4 })
    assert_equal "", Notes::Mentions.tokenize(nil, {})
  end

  test "display is the reverse, for the edit form, and leaves a deleted user's token alone" do
    dana = users(:two).tap { |user| user.update!(name: "Dana") }

    text, names = Notes::Mentions.display("Ask @[#{dana.id}] or @[999999]", { dana.id => dana })

    assert_equal "Ask @Dana or @[999999]", text
    assert_equal({ "Dana" => dana.id }, names)
  end
end
