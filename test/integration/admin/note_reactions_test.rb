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
    as(users(:two)) { Notes::React.call(@note, emoji: "🎉", on: true) }
    sign_in_as(users(:reader))
  end

  def frame = { "Turbo-Frame" => "notes" }

  test "a chip per emoji with its count and who, the viewer's own marked, and the set to add from" do
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }
    assert_redirected_to "#{@path}?shown=#{@note.id}"

    get @path, headers: frame

    assert_select "#note-thread-#{@thread.id}-messages #note-message-#{@note.id} [data-note-reactions=open]" do
      # A press says the state it is meant to reach: on for someone else's emoji, off for one's own.
      assert_select "form:has(input[name=on][value=true]) button[data-reaction='🎉'][title='Dana']:not([data-mine])", text: /🎉\s*1/
      assert_select "form:has(input[name=on][value=false]) button[data-reaction='👍'][data-mine][aria-pressed=true]", text: /👍\s*1/
      # The names a screen reader says: the emoji in words, how many, whose.
      assert_select "button[data-reaction='🎉'][aria-label='party popper, 1 reaction, by Dana']"
      assert_select "button[data-reaction='👍'][aria-label='thumbs up, 1 reaction, yours']"
      assert_select "details[data-reaction-add]:not([class~='opacity-0']) form:has(input[name=on][value=true]) button[name=emoji]", count: Notes::EMOJI.size
      assert_select "details[data-reaction-add] button[name=emoji][aria-label='React with thumbs up']", text: "👍"
      assert_select "form[data-turbo-frame=notes]", minimum: 3
    end
    # "React" is in everyone's menu, for touch.
    assert_select "#note-message-#{@note.id} [role=menu] button[data-note-react]", text: "React"
    # No reaction's form is inside another form: not the reply's, not an edit's.
    assert_select "form form", count: 0
    assert_select "form[data-note-composer] [data-note-reactions]", count: 0
  end

  test "a reaction taken back takes its chip with it; the same request twice ends in the same place" do
    2.times { post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" } }
    assert_equal [ "👍" ], Notes::Reaction.where(user: users(:reader)).pluck(:emoji)
    # Anything but a true value takes it back: "false", nothing at all.
    2.times { post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "false" } }
    assert_empty Notes::Reaction.where(user: users(:reader))
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "🎉" }
    assert_redirected_to "#{@path}?shown=#{@note.id}"
    assert_empty Notes::Reaction.where(user: users(:reader))

    get @path, headers: frame
    assert_select "button[data-reaction='👍']", count: 0
    assert_select "button[data-reaction='🎉']", count: 1
  end

  # Only the form's own word gives a reaction. A boolean cast read every
  # string that is not a false value as true, so `on=banana` gave one.
  test "a forged value for on gives no reaction: only the word true does" do
    %w[banana 1 TRUE yes on t].each do |forged|
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: forged }
      assert_redirected_to "#{@path}?shown=#{@note.id}"
      assert_empty Notes::Reaction.where(user: users(:reader)), "on=#{forged} gave a reaction"
    end

    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }
    assert_equal [ "👍" ], Notes::Reaction.where(user: users(:reader)).pluck(:emoji)
    # ... and anything else takes it back.
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "banana" }
    assert_empty Notes::Reaction.where(user: users(:reader))
  end

  test "an emoji that was not offered is refused in the thread, under its message, and nothing is stored" do
    assert_no_difference -> { Notes::Reaction.count } do
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "<script>alert(1)</script>", on: "true" }, headers: frame
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

    as(users(:one)) { Notes::EMOJI.first(6).each { |emoji| Notes::React.call(@note, emoji: emoji, on: true) } }
    11.times do |index|
      reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Reply #{index}") }.record
      [ users(:one), users(:two) ].each { |user| as(user) { Notes::React.call(reply, emoji: Notes::EMOJI[index], on: true) } }
    end
    sign_in_as(users(:reader))
    get @path, headers: frame # reads what the replies delivered

    many = capture_sql { get @path, headers: frame }
    assert_select "[data-note-reactions]", count: 12
    assert_equal one.size, many.size
    assert_equal 1, many.grep(/FROM "note_reactions"/).size
    assert_equal 2, many.grep(/FROM "users"/).size
    assert_select "button[data-reaction='#{Notes::EMOJI.first}'][title='#{Notes.name_of(users(:one))}']"
  end

  test "the list reads no reactions" do
    assert_empty capture_sql { get "/cs-studio/notes/page/#{@page.id}", headers: frame }.grep(/note_reactions/)
  end

  test "a reaction on a folded message draws the thread with the fold open" do
    replies = as(users(:two)) { Array.new(4) { |index| Notes::Reply.call(@thread, body: "Reply #{index}").record } }
    post "#{@path}/messages/#{replies.first.id}/reactions", params: { emoji: "👍", on: "true" }
    follow_redirect!(headers: frame)

    assert_select "details[data-note-fold][open] #note-message-#{replies.first.id} button[data-reaction='👍'][data-mine]"
    get @path, headers: frame
    assert_select "details[data-note-fold]:not([open])"
  end

  test "a message that is being edited keeps its chips under the form, disabled, and has no React in its menu" do
    sign_in_as(users(:two))
    get "#{@path}?edit=#{@note.id}", headers: frame

    assert_select "#note-message-#{@note.id} form[data-note-composer] ~ [data-note-reactions=disabled][class~='opacity-50'][class~='pointer-events-none']" do
      assert_select "button[data-reaction='🎉'][disabled]"
      assert_select "button[data-reaction-add][disabled]"
      assert_select "button:not([disabled])", count: 0
      assert_select "details", count: 0
    end
    assert_select "#note-message-#{@note.id} [data-note-react]", count: 0
    assert_select "form form", count: 0
  end

  # The handoff's decision 26: no row under a message nobody reacted to; its
  # way to the set is in the meta line, just left of the "⋯" menu.
  test "a message nobody reacted to has no reactions row: its add control is in the meta line, shown on hover or focus" do
    reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Plain") }.record
    get @path, headers: frame

    assert_select "#note-message-#{reply.id} [data-note-reactions]", count: 0
    assert_select "#note-message-#{reply.id} button[data-reaction]", count: 0
    hidden_at_rest = "[class~='opacity-0'][class~='group-hover/note:opacity-100'][class~='group-focus-within/note:opacity-100'][class~='open:opacity-100']"
    meta = "#note-message-#{reply.id}[class~='group/note'] > div:first-child > details[data-reaction-add=meta]#{hidden_at_rest}"
    assert_select "#{meta} + [data-controller='admin--menu']" # just left of the "⋯" menu
    assert_select "#{meta} > summary[aria-label='Add a reaction'][class~='size-6'][class~='text-meta']"
    assert_select "#{meta} form[data-turbo-frame=notes]:has(input[name=on][value=true]) button[name=emoji]", count: Notes::EMOJI.size
    assert_select "#note-message-#{reply.id} [data-note-react]", text: "React"

    # With a reaction: the add chip at the end of the chip row, always shown, and nothing in the meta line.
    assert_select "#note-message-#{@note.id} [data-note-reactions] > details[data-reaction-add=row]:last-child:not([class~='opacity-0'])"
    assert_select "#note-message-#{@note.id} details[data-reaction-add]", count: 1
  end

  test "a message nobody reacted to, while it is being edited, has neither a row nor the meta-line control" do
    reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Plain") }.record
    sign_in_as(users(:two))
    get "#{@path}?edit=#{reply.id}", headers: frame

    assert_select "#note-message-#{reply.id} form[data-note-composer]"
    assert_select "#note-message-#{reply.id} [data-note-reactions], #note-message-#{reply.id} [data-reaction-add], #note-message-#{reply.id} [data-note-react]", count: 0
  end

  test "a resolved thread shows its reactions read-only: no button, no add chip, no React; and a request sent all the same is refused" do
    reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Plain") }.record
    as(users(:two)) { assert Notes::Resolve.call(@thread).ok? }
    get @path, headers: frame

    assert_select "#note-message-#{@note.id} [data-note-reactions=closed]" do
      assert_select "span[data-reaction='🎉'][role=img][title='Dana'][aria-label='party popper, 1 reaction, by Dana']", text: /🎉\s*1/
      assert_select "button, form, details", count: 0
    end
    assert_select "#note-message-#{reply.id} [data-note-reactions]", count: 0
    assert_select "[data-note-react], [data-reaction-add]", count: 0
    # A reader's menu had nothing but React in it: no menu at all now.
    assert_select "#note-message-#{@note.id} [role=menu]", count: 0

    assert_no_difference -> { Notes::Reaction.count } do
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }, headers: frame
    end
    assert_response :unprocessable_entity
    assert_select "#note-message-#{@note.id} [role=alert]", text: "This thread is resolved. Reopen it to react."
  end

  test "a reaction outside the scope is not found; on a message of another thread or record it is gone" do
    other = as(users(:two)) { Notes::Start.call(@page, body: "Another") }.record
    elsewhere = as(users(:two)) { Notes::Start.call(create_page(title: "Elsewhere"), body: "Far") }.record
    [ other, elsewhere ].each do |thread|
      post "#{@path}/messages/#{thread.first_message.id}/reactions", params: { emoji: "👍", on: "true" }
      assert_redirected_to "/cs-studio/notes/page/#{@page.id}?notice=gone"
    end
    post "/cs-studio/notes/page/#{@page.id}/threads/#{elsewhere.id}/messages/#{elsewhere.first_message.id}/reactions", params: { emoji: "👍", on: "true" }
    assert_redirected_to "/cs-studio/notes/page/#{@page.id}?notice=gone"
    assert_equal 1, Notes::Reaction.count

    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))
    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }
    assert_response :not_found
    assert_equal 1, Notes::Reaction.count
  end

  test "a reaction on a trashed page is not found, and nothing is stored" do
    Page.where(id: @page.id).update_all(trashed_at: Time.current)

    post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }

    assert_response :not_found
    assert_equal 1, Notes::Reaction.count
  end

  test "the signal names the tab that reacted" do
    stream = Notes::Signals.record_stream("Page", @page.id)

    assert_broadcast_on(stream, { kind: "threads", thread_id: @thread.id, origin: "tab-12345678" }) do
      post "#{@path}/messages/#{@note.id}/reactions", params: { emoji: "👍", on: "true" }, headers: { "X-Notes-Tab" => "tab-12345678" }
    end
  end
end
