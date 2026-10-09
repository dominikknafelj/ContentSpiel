require "test_helper"

class Admin::NoteWritesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
    @base = "/cs-studio/notes/page/#{@page.id}"
    users(:two).update!(name: "Dana")
  end

  test "a note on a block is started from the form, with the picker's name turned into a token" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Ask @Dana about this", mention_names: { "Dana" => users(:two).id }.to_json,
      subject: "ContentBlock-#{@block.id}", quote: "€49", locale: "en" }

    thread = Notes::Thread.order(:id).last
    assert_redirected_to "#{@base}/threads/#{thread.id}"
    assert_response :see_other
    assert_equal [ @block, "€49", "editor", "Ask @[#{users(:two).id}] about this" ], [ thread.subject, thread.quote, thread.origin_view, thread.first_message.body ]
    assert_equal [ [ users(:two).id, "mention" ] ], Notes::Delivery.where(thread: thread).pluck(:user_id, :reason)
  end

  test "a failed note re-renders the frame at 422 with the text, the names and the reason kept" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password-password", name: "Sam")
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Ask @Sam", mention_names: { "Sam" => stranger.id }.to_json }, headers: { "Turbo-Frame" => "notes" }

    assert_response :unprocessable_entity
    # The refusal names nobody (`Notes::Authorization#mention_errors`).
    assert_select "#notes-new [role=alert]", text: "Someone you mentioned can't see this page."
    assert_select "#notes-new textarea[name=body]", text: "Ask @Sam"
    assert_select "#notes-new input[name=mention_names]" do |inputs|
      assert_equal({ "Sam" => stranger.id }, JSON.parse(inputs.first["value"]))
    end
    assert_equal 1, Notes::Thread.count
  end

  test "reply, edit and delete" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "Yes" }
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    reply = @thread.messages.last

    patch "#{@base}/threads/#{@thread.id}/messages/#{reply.id}", params: { body: "Yes, it is" }
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    assert_equal "Yes, it is", reply.reload.body

    delete "#{@base}/threads/#{@thread.id}/messages/#{reply.id}"
    assert_redirected_to "#{@base}/threads/#{@thread.id}"
    assert_not Notes::Message.exists?(reply.id)
  end

  test "editing someone else's note is a 403 in the frame, with the reason in that message's form" do
    sign_in_as(users(:reader))

    patch "#{@base}/threads/#{@thread.id}/messages/#{@thread.first_message.id}", params: { body: "Mine" }, headers: { "Turbo-Frame" => "notes" }

    assert_response :forbidden
    assert_select "turbo-frame#notes #note-thread-#{@thread.id} #note-message-#{@thread.first_message.id} [role=alert]", text: /Only the person who wrote a note/
    assert_equal "Is this right?", @thread.first_message.reload.body
  end

  test "deleting the last message answers the frame without the thread" do
    sign_in_as(users(:two))

    delete "#{@base}/threads/#{@thread.id}/messages/#{@thread.first_message.id}"

    assert_redirected_to @base
    assert_equal 0, Notes::Thread.count
  end

  test "resolve, reopen, pin, unpin, follow and unfollow" do
    sign_in_as(users(:two))

    { "resolve" => -> { @thread.reload.resolved? }, "reopen" => -> { @thread.reload.open? }, "pin" => -> { @thread.reload.pinned },
      "unpin" => -> { !@thread.reload.pinned }, "unfollow" => -> { !Notes::Follow.find_by(thread: @thread, user: users(:two)).following },
      "follow" => -> { Notes::Follow.find_by(thread: @thread, user: users(:two)).following } }.each do |change, done|
      post "#{@base}/threads/#{@thread.id}/#{change}"
      assert_redirected_to "#{@base}/threads/#{@thread.id}"
      assert done.call, change
    end
  end

  test "a reader's pin is refused in the frame, and the thread's buttons follow the viewer's rights" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/pin", headers: { "Turbo-Frame" => "notes" }
    assert_response :forbidden
    assert_select "#note-thread-#{@thread.id} [role=alert]"

    get "#{@base}/threads/#{@thread.id}", headers: { "Turbo-Frame" => "notes" }
    assert_select "#note-thread-#{@thread.id} [data-note-actions]" do
      assert_select "form[action$='/follow']"
      assert_select "form[action$='/pin']", count: 0
    end
    assert_select "#note-thread-#{@thread.id}-reply form[action$='/resolve']"
    assert_select "#note-message-#{@thread.first_message.id} form", count: 0 # someone else's note: nothing to edit or delete
    assert_select "#note-thread-#{@thread.id}-reply form[data-controller='admin--note-composer'][data-turbo-frame=notes] textarea[name=body]"
  end

  # Review Focus 3.
  test "a reply to a thread whose block was deleted meanwhile comes back to the frame saying so" do
    on_block = as(users(:two)) { Notes::Start.call(@block, body: "About this block") }.record
    assert ContentBlocks::Destroy.call(@block).ok?
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{on_block.id}/messages", params: { body: "Too late" }

    assert_redirected_to "#{@base}?notice=gone"
    follow_redirect!
    assert_select "[role=status]", text: /This note is gone/
  end

  test "every write is not found outside the read scope, and a thread of another record is gone, not written" do
    other = create_page(title: "Other")
    elsewhere = as(users(:two)) { Notes::Start.call(other, body: "Elsewhere") }.record
    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))

    post "#{@base}/threads", params: { body: "Hi" }
    assert_response :not_found
    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "Hi" }
    assert_response :not_found
    post "#{@base}/threads/#{@thread.id}/resolve"
    assert_response :not_found

    sign_in_as(users(:reader))
    post "#{@base}/threads/#{elsewhere.id}/messages", params: { body: "Hi" }
    assert_redirected_to "#{@base}?notice=gone"
    assert_equal 1, elsewhere.messages.count
  end

  test "the new-note form is on the record, or on the block the URL names, with the quote" do
    sign_in_as(users(:reader))

    get @base, params: { compose: "ContentBlock-#{@block.id}", note_quote: "€49 a month" }, headers: { "Turbo-Frame" => "notes" }

    assert_select "#notes-new input[type=hidden][name=subject][value='ContentBlock-#{@block.id}']"
    assert_select "#notes-new input[type=hidden][name=quote][value='€49 a month']"
    assert_select "#notes-new blockquote", text: "€49 a month"

    get @base, params: { compose: "ContentBlock-999999" }, headers: { "Turbo-Frame" => "notes" }
    assert_select "#notes-new input[name=subject][value='']"

    get @base, headers: { "Turbo-Frame" => "notes" }
    assert_select "#notes-new", count: 0
    assert_select "a[data-note-new-link][href='#{@base}?compose=Page-#{@page.id}']"
  end

  test "a failed note on a block keeps the block and the quote it was on" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: " ", subject: "ContentBlock-#{@block.id}", quote: "€49" }, headers: frame

    assert_response :unprocessable_entity
    assert_select "#notes-new [role=alert]", text: "Write something first."
    assert_select "#notes-new input[name=subject][value='ContentBlock-#{@block.id}']"
    assert_select "#notes-new input[name=quote][value='€49']"
    assert_select "#notes-new blockquote", text: "€49"
    assert_select "#notes-new h3", text: "New note on Rich text"
  end

  # `Notes::SetFollowing` reads any truthy value as "follow", and a form's
  # "false" and "0" are truthy strings: the path decides, with a literal.
  test "follow and unfollow are decided by the path, whatever a following parameter says" do
    sign_in_as(users(:reader))
    row = -> { Notes::Follow.find_by(thread: @thread, user: users(:reader))&.following }

    %w[false 0].each do |forged|
      post "#{@base}/threads/#{@thread.id}/follow", params: { following: forged }
      assert_equal true, row.call, "follow with following=#{forged}"
    end
    %w[true 1].each do |forged|
      post "#{@base}/threads/#{@thread.id}/unfollow", params: { following: forged }
      assert_equal false, row.call, "unfollow with following=#{forged}"
    end

    get "#{@base}/threads/#{@thread.id}", headers: frame
    assert_select "[data-note-actions] form[action$='/follow'] button", text: "Notify me"
  end

  test "the menu of a message: Edit and Delete on one's own, Delete alone for a moderator, nothing for anyone else" do
    reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "Ask @[#{users(:two).id}]") }.record
    thread_url = "#{@base}/threads/#{@thread.id}"

    sign_in_as(users(:reader))
    get thread_url, headers: frame
    assert_select "#note-message-#{reply.id} [role=menu]" do
      # Neither link is prefetched: the thread's GET marks it read.
      assert_select "a[data-note-edit][data-turbo-frame=notes][data-turbo-prefetch=false][href='#{thread_url}?edit=#{reply.id}']", text: "Edit"
      assert_select "a[data-note-delete][data-turbo-frame=notes][data-turbo-prefetch=false][href='#{thread_url}?delete=#{reply.id}']", text: "Delete"
    end
    assert_select "#note-message-#{@thread.first_message.id} [role=menu]", count: 0
    assert_select "#note-thread-#{@thread.id}-messages form[data-note-composer]", count: 0 # no edit form until one is asked for

    sign_in_as(users(:one)) # the owner moderates, and wrote neither
    get thread_url, headers: frame
    assert_select "#note-message-#{reply.id} [role=menu]" do
      assert_select "a[data-note-edit]", count: 0
      assert_select "a[data-note-delete]", text: "Delete"
    end
  end

  test "Edit draws that one message's form with names for tokens, and Delete its question; neither for someone else's note" do
    reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "Ask @[#{users(:two).id}]") }.record
    thread_url = "#{@base}/threads/#{@thread.id}"
    sign_in_as(users(:reader))

    get thread_url, params: { edit: reply.id }, headers: frame
    assert_select "#note-message-#{reply.id} form[data-note-composer='message-#{reply.id}'][data-turbo-frame=notes][action='#{thread_url}/messages/#{reply.id}']" do
      assert_select "input[name=_method][value=patch]"
      assert_select "textarea[name=body]", text: "Ask @Dana"
      assert_select "input[name=mention_names]" do |inputs|
        assert_equal({ "Dana" => users(:two).id }, JSON.parse(inputs.first["value"]))
      end
    end
    assert_select "#note-message-#{reply.id} a[data-note-cancel][href='#{thread_url}']", text: "Cancel"
    assert_select "#note-thread-#{@thread.id}-messages form[data-note-composer]", count: 1

    get thread_url, params: { delete: reply.id }, headers: frame
    assert_select "#note-message-#{reply.id} [data-note-delete-question]", text: /Delete this note\?/ do
      assert_select "form[data-turbo-frame=notes][action='#{thread_url}/messages/#{reply.id}'] input[name=_method][value=delete]"
    end

    first = @thread.first_message
    get thread_url, params: { edit: first.id, delete: first.id }, headers: frame
    assert_select "#note-message-#{first.id} form", count: 0
  end

  test "an edit that is refused comes back with its form open and the typed text in it" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password-password", name: "Sam")
    reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "Yes") }.record
    sign_in_as(users(:reader))

    patch "#{@base}/threads/#{@thread.id}/messages/#{reply.id}", params: { body: "Ask @Sam", mention_names: { "Sam" => stranger.id }.to_json }, headers: frame

    assert_response :unprocessable_entity
    assert_select "#note-message-#{reply.id} form[data-note-composer='message-#{reply.id}']" do
      assert_select "[role=alert]", text: "Someone you mentioned can't see this page."
      assert_select "textarea[name=body]", text: "Ask @Sam"
    end
    assert_equal "Yes", reply.reload.body
  end

  test "a reply that is refused comes back in the reply's own form, with the text" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "x" * 4001 }, headers: frame

    assert_response :unprocessable_entity
    assert_select "#note-thread-#{@thread.id}-reply form[data-note-composer='thread-#{@thread.id}']" do
      assert_select "[role=alert]", text: "A note can be at most 4,000 characters."
      assert_select "textarea[name=body]", text: "x" * 4001
    end
    assert_equal 1, @thread.messages.count
  end

  # Review Focus 3, the other half: the thread was there when the request
  # arrived and went while the service ran. A notes service's failure has no
  # record, and "gone" is a failure like any other.
  test "a thread that goes while the reply's service runs answers the list with the sentence, and a failure with no record is drawn, never raised" do
    sign_in_as(users(:reader))
    gone = ApplicationService::Result.failure(nil, [ "This note is gone: it was deleted, or what it was on was." ])
    thread = @thread

    answering(Notes::Reply, -> { thread.destroy! && gone }) { post "#{@base}/threads/#{thread.id}/messages", params: { body: "Too late" } }
    assert_redirected_to "#{@base}?notice=gone"

    other = as(users(:two)) { Notes::Start.call(@page, body: "Still here") }.record
    answering(Notes::Reply, -> { gone }) { post "#{@base}/threads/#{other.id}/messages", params: { body: "Kept" }, headers: frame }
    assert_response :unprocessable_entity
    assert_select "#note-thread-#{other.id}-reply [role=alert]", text: /This note is gone/
    assert_select "#note-thread-#{other.id}-reply textarea[name=body]", text: "Kept"

    answering(Notes::Resolve, -> { gone }) { post "#{@base}/threads/#{other.id}/resolve", headers: frame }
    assert_response :unprocessable_entity
    assert_select "#note-thread-#{other.id} [role=alert]", text: /This note is gone/

    first = other.first_message
    answering(Notes::DeleteMessage, -> { gone }) { delete "#{@base}/threads/#{other.id}/messages/#{first.id}", headers: frame }
    assert_response :unprocessable_entity
    assert_select "#note-message-#{first.id} [role=alert]", text: /This note is gone/
  end

  test "a message that is gone, in a thread that is still there, is the list with the sentence" do
    sign_in_as(users(:reader))

    patch "#{@base}/threads/#{@thread.id}/messages/999999", params: { body: "Hi" }
    assert_redirected_to "#{@base}?notice=gone"
    delete "#{@base}/threads/#{@thread.id}/messages/999999"
    assert_redirected_to "#{@base}?notice=gone"
    post "#{@base}/threads/999999/resolve"
    assert_redirected_to "#{@base}?notice=gone"
  end

  # Note text reaches no log (decision D14). The forms' names are top-level
  # `body` and `quote`, filtered by the controller they arrive at
  # (`config/initializers/filter_parameter_logging.rb`).
  test "a posted note's text, quote and picked names are filtered from the request's logged parameters" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "A secret thought", quote: "€49 a month", mention_names: { "Dana" => users(:two).id }.to_json, subject: "" }
    assert_response :see_other
    assert_equal %w[[FILTERED] [FILTERED] [FILTERED]], request.filtered_parameters.values_at("body", "quote", "mention_names")
    thread = Notes::Thread.order(:id).last
    assert_equal [ "A secret thought", "€49 a month" ], [ thread.first_message.body, thread.quote ] # the filter masks the log's copy only

    post "#{@base}/threads/#{thread.id}/messages", params: { body: "A second thought" }
    assert_equal "[FILTERED]", request.filtered_parameters["body"]
    patch "#{@base}/threads/#{thread.id}/messages/#{thread.messages.last.id}", params: { body: "A third thought" }
    assert_equal "[FILTERED]", request.filtered_parameters["body"]
  end

  # The passage a GET carries to the new-note form is in the URL, and Rails
  # writes the URL on the "Started GET" line with each pair of the query
  # string filtered on its own (`request.filtered_path`): no controller to
  # scope by. So the GET's name is `note_quote`, filtered wherever it appears.
  test "the quote a GET carries is note_quote, masked on the request's logged path and parameters; ?quote= on that GET is ignored" do
    sign_in_as(users(:reader))

    get @base, params: { compose: "ContentBlock-#{@block.id}", note_quote: "€49 a month" }, headers: frame
    assert_equal "#{@base}?compose=ContentBlock-#{@block.id}&note_quote=[FILTERED]", request.filtered_path
    assert_equal "[FILTERED]", request.filtered_parameters["note_quote"]
    assert_not_includes request.filtered_path, "49"
    assert_select "#notes-new input[type=hidden][name=quote][value='€49 a month']"
    assert_select "#notes-new blockquote", text: "€49 a month"

    get @base, params: { compose: "ContentBlock-#{@block.id}", quote: "€49 a month" }, headers: frame
    assert_select "#notes-new input[type=hidden][name=quote][value='']"
    assert_select "#notes-new blockquote", count: 0
  end

  test "a draft is kept per person: the composer is handed the signed-in user's id" do
    sign_in_as(users(:reader))

    get @base, params: { compose: "Page-#{@page.id}" }, headers: frame
    assert_select "#notes-new form[data-admin--note-composer-user-value='#{users(:reader).id}']"
    get "#{@base}/threads/#{@thread.id}", headers: frame
    assert_select "#note-thread-#{@thread.id}-reply form[data-admin--note-composer-user-value='#{users(:reader).id}']"
  end

  test "Edit, Delete or a refused edit of a message folded into Show more opens the fold" do
    replies = as(users(:reader)) { 4.times.map { |index| Notes::Reply.call(@thread, body: "Reply #{index}").record } }
    folded = replies.first # five messages: the first and the last two show, the second and third are folded
    thread_url = "#{@base}/threads/#{@thread.id}"
    fold = "#note-thread-#{@thread.id}-messages details[data-note-fold]"
    sign_in_as(users(:reader))

    get thread_url, headers: frame
    assert_select "#{fold} #note-message-#{folded.id}"
    assert_select "#{fold}[open]", count: 0

    get thread_url, params: { edit: folded.id }, headers: frame
    assert_select "#{fold}[open] #note-message-#{folded.id} form[data-note-composer='message-#{folded.id}']"

    get thread_url, params: { delete: folded.id }, headers: frame
    assert_select "#{fold}[open] #note-message-#{folded.id} [data-note-delete-question]"

    patch "#{thread_url}/messages/#{folded.id}", params: { body: "x" * 4001 }, headers: frame
    assert_response :unprocessable_entity
    assert_select "#{fold}[open] #note-message-#{folded.id} form[data-note-composer='message-#{folded.id}'] [role=alert]"

    get thread_url, params: { edit: replies.last.id }, headers: frame # not a folded one
    assert_select "#{fold}[open]", count: 0
  end

  # A message is looked up among THIS thread's, never by its id alone.
  test "a message of another thread, of this record or of another the actor reads, is a 303 to the list saying gone on edit and delete, and nothing is written" do
    sibling = as(users(:reader)) { Notes::Start.call(@block, body: "Same record") }.record.first_message
    other = create_page(title: "Other")
    elsewhere = as(users(:reader)) { Notes::Start.call(other, body: "Other record") }.record.first_message
    sign_in_as(users(:reader)) # the author of both, so only the lookup stands in the way

    [ sibling, elsewhere ].each do |foreign|
      patch "#{@base}/threads/#{@thread.id}/messages/#{foreign.id}", params: { body: "Rewritten" }
      assert_response :see_other
      assert_redirected_to "#{@base}?notice=gone"
      delete "#{@base}/threads/#{@thread.id}/messages/#{foreign.id}"
      assert_response :see_other
      assert_redirected_to "#{@base}?notice=gone"

      assert_equal [ foreign.body, nil ], foreign.reload.then { |record| [ record.body, record.edited_at ] }
    end
    assert_equal [ "Same record", "Other record" ], [ sibling, elsewhere ].map { |record| record.reload.body }
    assert_equal 1, @thread.messages.count
  end

  # ...and by nothing else: `body` is a post's and a block's own attribute.
  # `Audit::Snapshot.scrub` drops every snapshot key `filter_parameters`
  # matches, so a bare `:body` there would take the text out of their audit
  # snapshots, and out of every other request's log line.
  test "the notes filter leaves a post's and a block's body where it was: in their audit snapshots and in other requests" do
    post_record = create_post(title: "News")
    as_owner do
      Posts::Save.call(post_record, translations: { "en" => { body: rich_doc("A post's body") } })
      ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc("A block's body") } })
    end

    assert_includes Audit::Snapshot.for(post_record.reload).fetch("body").to_json, "A post's body"
    assert_includes Audit::Snapshot.for(@block.reload).fetch("body").to_json, "A block's body"
    assert_equal({ "id" => 1, "body" => "kept", "quote" => "kept" }, Audit::Snapshot.scrub("id" => 1, "body" => "kept", "quote" => "kept", "mention_names" => "dropped"))

    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    elsewhere = { "controller" => "admin/posts", "body" => "A post's body", "post" => { "body" => "nested" }, "quote" => "a quote" }
    assert_equal elsewhere, filter.filter(elsewhere)
  end

  private

  def frame = { "Turbo-Frame" => "notes" }

  # `service.call` answers what `answer` returns for the length of the block:
  # the outcome of a race no single request can make (the thread, or what it
  # is on, going between the controller's lookup and the service's lock).
  def answering(service, answer)
    service.define_singleton_method(:call) { |*, **| answer.call }
    yield
  ensure
    service.singleton_class.send(:remove_method, :call)
  end

  test "a record's open threads as JSON for the mind graph's card: first message, author, replies, no markup" do
    users(:two).update!(name: "Dana")
    post_record = create_post(title: "Hello")
    thread = as(users(:two)) { Notes::Start.call(post_record, body: "Ask @[#{users(:reader).id}] <b>now</b> " + ("x" * 200), origin_view: "mind_graph") }.record
    as(users(:reader)) { Notes::Reply.call(thread, body: "On it") }
    sign_in_as(users(:reader))

    get "/cs-studio/notes/post/#{post_record.id}/threads"

    assert_response :success
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    assert_equal 1, body["open"]
    row = body["threads"].first
    assert_equal [ thread.id, "Dana", 1, false ], row.values_at("id", "author", "replies", "pinned")
    assert_equal true, row["unread"] # the first message mentions the reader, and reading a list marks nothing read (P10)
    assert_equal false, row["mine"] # Dana wrote it, not the reader
    assert row["text"].start_with?("Ask @reader@example.com <b>now</b> x")
    assert_operator row["text"].length, :<=, 140
    assert_equal 1, Notes::Delivery.unread.where(user: users(:reader)).count, "reading the card's list marked a delivery read"
  end

  test "the card's JSON lists only open threads, pinned first, names a deleted author as nobody and says which are the viewer's own" do
    post_record = create_post(title: "Hello")
    gone = User.create!(email_address: "gone@example.com", password: "password-password", name: "Gone")
    first = as(users(:two)) { Notes::Start.call(post_record, body: "First") }.record
    pinned = as(users(:two)) { Notes::Start.call(post_record, body: "Pinned") }.record
    as(users(:two)) { Notes::Pin.call(pinned) }
    as(users(:two)) { Notes::Resolve.call(Notes::Start.call(post_record, body: "Done").record) }
    own = as(users(:reader)) { Notes::Start.call(post_record, body: "Mine") }.record
    Notes::Message.where(thread: first).update_all(author_id: gone.id)
    gone.destroy!
    sign_in_as(users(:reader))

    get "/cs-studio/notes/post/#{post_record.id}/threads"

    body = response.parsed_body
    assert_equal 3, body["open"]
    assert_equal [ pinned.id, own.id, first.id ], body["threads"].map { |row| row["id"] }
    assert_equal [ true, false, false ], body["threads"].map { |row| row["pinned"] }
    assert_equal [ false, true, false ], body["threads"].map { |row| row["mine"] }
    assert_nil body["threads"].last["author"]
  end

  test "the card's JSON is not found for a post outside the read scope, a trashed one and an id that names nothing" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    other = create_post(title: "Other")
    as(users(:two)) { Notes::Start.call(other, body: "Not for the author") }
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    sign_in_as(users(:author))

    [ other.id, gone.id, 0 ].each do |id|
      get "/cs-studio/notes/post/#{id}/threads"
      assert_response :not_found
      assert_not_includes response.body, "Not for the author"
    end
  end

  test "a note is started over JSON, and a refusal is JSON too" do
    post_record = create_post(title: "Hello")
    sign_in_as(users(:reader))

    post "/cs-studio/notes/post/#{post_record.id}/threads", params: { body: "From the graph", view: "mind_graph" }, headers: { "Accept" => "application/json" }
    assert_response :created
    assert_equal [ "mind_graph", post_record ], Notes::Thread.find(response.parsed_body["id"]).then { |thread| [ thread.origin_view, thread.subject ] }

    post "/cs-studio/notes/post/#{post_record.id}/threads", params: { body: " " }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal [ "Write something first." ], response.parsed_body["errors"]
  end
end
