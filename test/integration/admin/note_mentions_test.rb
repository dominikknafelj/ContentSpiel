require "test_helper"

# The composer's mention picker (notes spec §3.2): not a directory.
class Admin::NoteMentionsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "password-password")
    sign_in_as(users(:reader))
  end

  def suggest(q) = get("/cs-studio/notes/page/#{@page.id}/mentions", params: { q: q }) && response.parsed_body

  # Someone without a name is the part of their address before the at sign
  # (the handoff's decision 36), and the whole address is still the hint.
  test "it lists users who may read the record, by name with the email as a hint, owners included" do
    users(:two).update!(name: "Dana Example")

    assert_equal [ { "id" => users(:two).id, "label" => "Dana Example", "hint" => "two@example.com", "initials" => "DE" } ], suggest("dana")
    assert_equal [ { "id" => users(:one).id, "label" => "one", "hint" => "one@example.com", "initials" => "on" } ], suggest("one@")
  end

  test "someone who may not read the record is never offered" do
    assert_equal [], suggest("stranger")
    assert_not_includes suggest("example.com").map { |row| row["id"] }, @stranger.id
  end

  test "six rows at most, from the first character on, and for a bare @ the first six readers" do
    10.times do |index|
      user = User.create!(email_address: "member#{index}@example.org", password: "password-password")
      AccessControl::Membership.create!(group: access_control_groups(:read_only), user: user)
    end

    assert_equal 6, suggest("member").size
    assert_equal 6, suggest("m").size
    assert_equal 6, suggest("").size
    assert(suggest("").none? { |row| row["id"] == @stranger.id })
  end

  test "it answers only for a record the asker may read" do
    sign_in_as(@stranger)

    get "/cs-studio/notes/page/#{@page.id}/mentions", params: { q: "two" }

    assert_response :not_found
  end

  # An invited person cannot sign in yet (`User.can_sign_in`): offering them
  # would send a note to someone who cannot read it.
  test "an invited person is never offered, even in a group that may read the record" do
    invited = invited_user("member-invited@example.com", groups: [ access_control_groups(:read_only) ])

    assert_not_includes suggest("member-invited").map { |row| row["id"] }, invited.id
    assert_not_includes suggest("").map { |row| row["id"] }, invited.id
  end
end
