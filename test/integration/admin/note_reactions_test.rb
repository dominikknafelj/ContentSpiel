require "test_helper"

class Admin::NoteReactionsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Shipped") }.record
    @note = @thread.first_message
    @path = "/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}"
    users(:two).update!(name: "Dana")
    as(users(:two)) { Notes::React.call(@note, emoji: "🎉") }
    sign_in_as(users(:reader))
  end

  def frame = { "Turbo-Frame" => "notes" }

  test "a chip per emoji with its count and who, the viewer's own marked, and the set to add from" do
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍" }
    assert_redirected_to "#{@path}?shown=#{@note.id}"

    get @path, headers: frame

    assert_select "#note-thread-#{@thread.id}-messages #note-message-#{@note.id} [data-note-reactions]" do
      assert_select "button[data-reaction='🎉'][title='Dana']:not([data-mine])", text: /🎉\s*1/
      assert_select "button[data-reaction='👍'][data-mine][aria-pressed=true]", text: /👍\s*1/
      assert_select "details[data-reaction-add] button[name=emoji]", count: Notes::EMOJI.size
      assert_select "form[data-turbo-frame=notes]", minimum: 3
    end
    # No reaction's form is inside another form: not the reply's, not an edit's.
    assert_select "form form", count: 0
    assert_select "form[data-note-composer] [data-note-reactions]", count: 0
  end

  test "the same emoji again takes it back, and the chip goes with its last reaction" do
    2.times { post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍" } }

    get @path, headers: frame
    assert_select "button[data-reaction='👍']", count: 0
    assert_select "button[data-reaction='🎉']", count: 1
  end

  test "an emoji that was not offered is refused in the thread, under its message, and nothing is stored" do
    assert_no_difference -> { Notes::Reaction.count } do
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "<script>alert(1)</script>" }, headers: frame
    end

    assert_response :unprocessable_entity
    assert_select "#note-message-#{@note.id} [role=alert]", text: /That reaction isn't available/
    assert_no_match(/alert\(1\)/, response.body)
  end

  # The pinned cost of the thread view (Task 15): one read for the reactions
  # of all its messages, and the people who reacted are named from the one
  # read of the people the thread names.
  test "the thread view costs the same statements with one reaction as with many, on one message or on twelve" do
    get @path, headers: frame
    one = capture_sql { get @path, headers: frame }
    assert_equal 1, one.grep(/FROM "note_reactions"/).size
    # The signed-in user, and everyone the thread names -- those who reacted among them.
    assert_equal 2, one.grep(/FROM "users"/).size

    as(users(:one)) { Notes::EMOJI.first(6).each { |emoji| Notes::React.call(@note, emoji: emoji) } }
    11.times do |index|
      reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Reply #{index}") }.record
      [ users(:one), users(:two) ].each { |user| as(user) { Notes::React.call(reply, emoji: Notes::EMOJI[index]) } }
    end
    sign_in_as(users(:reader))
    get @path, headers: frame # reads what the replies delivered

    many = capture_sql { get @path, headers: frame }
    assert_select "[data-note-reactions]", count: 12
    assert_equal one.size, many.size
    assert_equal 1, many.grep(/FROM "note_reactions"/).size
    assert_equal 2, many.grep(/FROM "users"/).size
    assert_select "button[data-reaction='#{Notes::EMOJI.first}'][title='#{users(:one).display_name}']"
  end

  test "the list reads no reactions" do
    assert_empty capture_sql { get "/cs-studio/notes/page/#{@page.id}", headers: frame }.grep(/note_reactions/)
  end

  test "a reaction on a folded message draws the thread with the fold open" do
    replies = as(users(:two)) { Array.new(4) { |index| Notes::Reply.call(@thread, body: "Reply #{index}").record } }
    post "#{@path}/messages/#{replies.first.id}/reactions", params: { emoji: "👍" }
    follow_redirect!(headers: frame)

    assert_select "details[data-note-fold][open] #note-message-#{replies.first.id} button[data-reaction='👍'][data-mine]"
    get @path, headers: frame
    assert_select "details[data-note-fold]:not([open])"
  end

  test "a message that is being edited shows its form and no reactions" do
    sign_in_as(users(:two))
    get "#{@path}?edit=#{@note.id}", headers: frame

    assert_select "#note-message-#{@note.id} form[data-note-composer]"
    assert_select "#note-message-#{@note.id} [data-note-reactions]", count: 0
  end

  test "a reaction outside the scope is not found; on a message of another thread or record it is gone" do
    other = as(users(:two)) { Notes::Start.call(@page, body: "Another") }.record
    elsewhere = as(users(:two)) { Notes::Start.call(create_page(title: "Elsewhere"), body: "Far") }.record
    [ other, elsewhere ].each do |thread|
      post "#{@path}/messages/#{thread.first_message.id}/reactions", params: { emoji: "👍" }
      assert_redirected_to "/cs-studio/notes/page/#{@page.id}?notice=gone"
    end
    post "/cs-studio/notes/page/#{@page.id}/threads/#{elsewhere.id}/messages/#{elsewhere.first_message.id}/reactions", params: { emoji: "👍" }
    assert_redirected_to "/cs-studio/notes/page/#{@page.id}?notice=gone"
    assert_equal 1, Notes::Reaction.count

    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍" }
    assert_response :not_found
    assert_equal 1, Notes::Reaction.count
  end

  test "a reaction on a trashed page is not found, and nothing is stored" do
    Page.where(id: @page.id).update_all(trashed_at: Time.current)

    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍" }

    assert_response :not_found
    assert_equal 1, Notes::Reaction.count
  end

  test "the signal names the tab that reacted" do
    stream = Notes::Signals.record_stream("Page", @page.id)

    assert_broadcast_on(stream, { kind: "threads", thread_id: @thread.id, origin: "tab-12345678" }) do
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍" }, headers: { "X-Notes-Tab" => "tab-12345678" }
    end
  end
end
