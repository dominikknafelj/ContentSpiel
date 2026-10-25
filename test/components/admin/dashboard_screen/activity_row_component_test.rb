require "test_helper"

class Admin::DashboardScreen::ActivityRowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one); Current.channel = :admin }
  teardown { Current.reset }

  def row_for(actor: users(:one), channel: :admin, title: "Hello", &change)
    post = Current.set(actor:, channel:) { create_post(title:, published: false) }
    change&.call(post)
    Dashboard::Activity.new(actor: users(:one), channel: :admin).rows.find { |r| r.record == post }
  end

  # A row of a change whose actor is handed over, a deleted user or nobody.
  def row_with(user:, user_id:, title:)
    row = row_for(title:)
    actor = Audit::Sentence::Actor.new(you: false, user:, user_id:, via_label: nil, none: false)
    row.with(sentence: row.sentence.with(actor:))
  end

  test "a person has a round avatar with their initial, the sentence links the title, and a draft shows its chip" do
    row = row_for
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row:)

    assert_selector "span.rounded-full.uppercase[aria-hidden=true]", exact_text: "on"
    assert_text "You created “Hello”" # the viewer's own change, as in the audit log
    assert_selector "a[href='/cs-studio/posts/#{row.record.id}']", text: "Hello"
    assert_text "Draft"
    assert_selector "time"
  end

  test "a change through an API token has the user's round avatar, names the user, says via the token's name and shows the MCP chip" do
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "Claude desktop")
    row = row_for(actor: token, channel: :mcp)
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row:)

    assert_selector "span.rounded-full.uppercase[aria-hidden=true]", exact_text: "tw"
    assert_text "#{users(:two).display_name} via Claude desktop created “Hello”"
    assert_selector ".admin-channel-chip[data-channel=mcp]", text: "MCP"
  end

  # The owner's O9: the dashboard's circle is the two-letter rule
  # (`PersonName.initials`) of the name the row shows, drawn upper-case.
  test "the circle is two letters of the name the row shows: two words, one word, a deleted user, System" do
    users(:two).update!(name: "Ada Lovelace")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two), title: "First"))
    assert_selector "span.rounded-full.uppercase", exact_text: "AL"

    users(:two).update!(name: "Δήμητρα")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two), title: "Second"))
    assert_selector "span.rounded-full.uppercase", exact_text: "Δή"

    assert_equal "ad", Admin::DashboardScreen::ActivityRowComponent.new(row: row_with(user: nil, user_id: 999_999, title: "Deleted")).initials
    assert_equal "Sy", Admin::DashboardScreen::ActivityRowComponent.new(row: row_with(user: nil, user_id: nil, title: "Nobody")).initials
  end

  # A user with no name is shown by the part of the address before the at
  # sign (PersonName.of), so the circle's letters are that part's letters,
  # not the whole address's: "a@example.com" is "a", not "ae".
  test "a user with no name has the letters of the part of the address before the at sign" do
    users(:two).update!(name: nil, email_address: "a@example.com")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two), title: "Local"))
    assert_selector "span.rounded-full.uppercase[aria-hidden=true]", exact_text: "a"
    assert_text "a@example.com"

    users(:two).update!(email_address: "o.neil@example.com")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two), title: "Dotted"))
    assert_selector "span.rounded-full.uppercase", exact_text: "on"
  end

  [ "<script>x</script>", "😀" * 60 ].each_with_index do |name, index|
    test "a token's name is escaped, whatever it holds (#{index})" do
      token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name:)
      render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: token, channel: :mcp))

      assert_no_selector "script"
      assert_text "via #{name}"
    end
  end

  test "a named user reads by name, not email" do
    users(:two).update!(name: "Ada Lovelace")
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: row_for(actor: users(:two)))

    assert_text "Ada Lovelace created"
    assert_no_text users(:two).email_address
  end

  test "a live record has no chip" do
    row = row_for { |post| Current.set(actor: users(:one), channel: :admin) { Posts::Save.call(post, attributes: { published: true }) } }
    row = Dashboard::Activity.new(actor: users(:one), channel: :admin).rows.find { |r| r.event.action == "post.published" }
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row:)

    assert_text "published “Hello”"
    assert_no_text "Draft"
    assert_no_text "Live"
  end

  test "a coalesced burst shows its span as the time's tooltip" do
    post = Current.set(actor: users(:one), channel: :admin) { create_post(title: "Typing", published: false) }
    event = Audit::Event.find_by!(subject_type: "Post", subject_id: post.id)
    target = Audit::Sentence::Target.new(post.title, Audit::Sentence.route_for(post))
    row = Dashboard::Activity::Row.new(event:, record: post, sentence: Audit::Sentence.build(event, viewer: users(:one), target:),
      at: Time.zone.local(2030, 1, 10, 9, 0), span_end: Time.zone.local(2030, 1, 10, 9, 40))
    render_inline Admin::DashboardScreen::ActivityRowComponent.new(row:)

    assert_selector "time[title='10 Jan 2030, 09:00 – 09:40']"
  end
end
