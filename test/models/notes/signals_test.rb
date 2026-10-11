require "test_helper"

# What is pushed (notes spec §6.1, decision D16): a kind and ids, after the
# outermost commit, and nothing for an action that was rolled back or refused.
#
# The first test is the rule's guard. It runs EVERY service under
# `app/services/notes/` (a new one without its entry in `CASES` fails it) and
# looks at every broadcast made on any stream while it runs: the broadcasts
# are read from Action Cable's own notification, not from a list of stream
# names, so one sent somewhere unexpected is seen too.
class Notes::SignalsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  TAB = "tab-12345678".freeze

  # What a payload may hold, and the closed set each value comes from: with
  # these there is no key a text, a title or a name could travel in.
  KEYS = { "delivery" => %w[kind delivery_id reason], "inbox" => %w[kind origin], "threads" => %w[kind thread_id origin] }.freeze
  ID = { "delivery" => "delivery_id", "threads" => "thread_id" }.freeze
  STREAMS = { "delivery" => /\Anotes:person:\d+\z/, "inbox" => /\Anotes:person:\d+\z/,
    "threads" => /\Anotes:record:(Page|Post|MediaAsset)-\d+\z/ }.freeze

  # One entry per notes service: who calls it, the call, how many signals the
  # record's stream gets, which person is told with which reason, and whose
  # inbox got smaller (`inbox`, default nobody's). Each is
  # built on `@thread`: started by `users(:two)`, mentioning `users(:reader)`,
  # so both follow it.
  CASES = {
    "Notes::Start" => -> {
      { actor: users(:two), call: -> { Notes::Start.call(@page, body: "A secret body for @[#{users(:reader).id}]", quote: "a secret quote") },
        record: 1, people: { reader: "mention" } }
    },
    "Notes::Reply" => -> {
      { actor: users(:reader), call: -> { Notes::Reply.call(@thread, body: "Another secret, @[#{users(:one).id}]") },
        record: 1, people: { two: "reply", one: "mention" } }
    },
    "Notes::EditMessage" => -> {
      message = @thread.first_message
      { actor: users(:two), call: -> { Notes::EditMessage.call(message, body: "A reworded secret for @[#{users(:one).id}]") },
        record: 1, people: { one: "mention" } }
    },
    "Notes::DeleteMessage" => -> {
      reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "A secret to delete") }.record
      { actor: users(:reader), call: -> { Notes::DeleteMessage.call(reply) }, record: 1, people: {}, inbox: [ :two ] }
    },
    "Notes::Resolve" => -> {
      { actor: users(:reader), call: -> { Notes::Resolve.call(@thread) }, record: 1, people: { two: "resolved" } }
    },
    "Notes::Reopen" => -> {
      as(users(:two)) { assert Notes::Resolve.call(@thread).ok? }
      { actor: users(:reader), call: -> { Notes::Reopen.call(@thread) }, record: 1, people: { two: "reopened" } }
    },
    "Notes::Pin" => -> {
      { actor: users(:two), call: -> { Notes::Pin.call(@thread) }, record: 1, people: {} }
    },
    "Notes::Unpin" => -> {
      as(users(:two)) { assert Notes::Pin.call(@thread).ok? }
      { actor: users(:two), call: -> { Notes::Unpin.call(@thread) }, record: 1, people: {} }
    },
    # The record's stream only: a reaction never writes a delivery.
    "Notes::React" => -> {
      note = @thread.first_message
      { actor: users(:reader), call: -> { Notes::React.call(note, emoji: "🎉", on: true) }, record: 1, people: {} }
    },
    # The actor's own rows: nobody else is signalled.
    "Notes::SetFollowing" => -> {
      { actor: users(:reader), call: -> { Notes::SetFollowing.call(@thread, following: false) }, record: 0, people: {} }
    },
    "Notes::MarkRead" => -> {
      { actor: users(:reader), call: -> { Notes::MarkRead.call(thread: @thread) }, record: 0, people: {}, inbox: [ :reader ] }
    },
    # Not a person's action on a note: it runs on a record in the trash too
    # (that is where a purge finds it), so it has no "gone" answer to check.
    "Notes::Remove" => -> {
      { actor: users(:two), call: -> { Notes::Remove.call(@page) }, record: 1, people: {}, inbox: [ :reader ], answers_gone: false }
    }
  }.freeze

  setup do
    @page = create_page(title: "A secret title", published: false)
    @record = Notes::Signals.record_stream("Page", @page.id)
    @reader = Notes::Signals.person_stream(users(:reader).id)
    @two = Notes::Signals.person_stream(users(:two).id)
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1", name: "A secret name")
  end

  def start(on = @page) = as(users(:two)) { Notes::Start.call(on, body: "A secret body for @[#{users(:reader).id}]", quote: "a secret quote") }.record

  def sent(stream) = broadcasts(stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  # Every broadcast made while the block runs, on whatever stream, as
  # `[stream, payload]` with the payload as a browser gets it.
  def capture_signals
    seen = []
    callback = ->(*, event) { seen << [ event[:broadcasting], ActiveSupport::JSON.decode(event[:message].to_json) ] }
    ActiveSupport::Notifications.subscribed(callback, "broadcast.action_cable") { yield seen }
    seen
  end

  def assert_ids_only(stream, payload)
    kind = payload["kind"]
    assert_includes KEYS.keys, kind, payload.inspect
    assert_match STREAMS.fetch(kind), stream
    assert_empty payload.keys - KEYS.fetch(kind), payload.inspect
    assert_kind_of Integer, payload[ID.fetch(kind)], payload.inspect if ID.key?(kind)
    assert_includes Notes::Delivery::REASONS, payload["reason"] if kind == "delivery"
    assert_match Notes::Signals::TAB, payload["origin"] if payload.key?("origin")
    assert_no_match(/secret|Dana|example\.com/i, payload.to_json)
  end

  def run_case(prepared, actor: prepared.fetch(:actor))
    Current.set(actor: actor, channel: :admin, notes_tab: TAB) { prepared.fetch(:call).call }
  end

  def services
    Dir[Rails.root.join("app/services/notes/*.rb")].map { |file| "Notes::#{File.basename(file, ".rb").camelize}" }
      .select { |name| name.constantize.is_a?(Class) && name.constantize < ApplicationService }
  end

  test "every notes service has its case here" do
    assert_equal services.sort, CASES.keys.sort, "a notes service without a case in CASES (or a case without its service)"
    assert_operator services.size, :>=, 12
  end

  CASES.each do |name, build|
    test "#{name}: ids only, after the outermost commit, and nothing when rolled back, refused or gone" do
      @thread = start
      users(:two).update!(name: "Dana")
      prepared = instance_exec(&build)
      thread_ids = Notes::Thread.where(container: @page).ids

      # Rolled back: the call succeeds inside a transaction that is open
      # around it. Nothing is sent while that one is open -- a signal sent
      # when the service's own savepoint was released would be here -- and
      # nothing when it rolls back.
      rolled_back = capture_signals do |seen|
        ActiveRecord::Base.transaction do
          assert run_case(prepared).ok?
          assert_empty seen, "sent before the outermost transaction committed"
          raise ActiveRecord::Rollback
        end
      end
      assert_empty rolled_back, "sent for a rolled-back action"

      # Refused: someone with no right at all.
      refused = capture_signals { assert run_case(prepared, actor: @stranger).denied? }
      assert_empty refused, "sent for a refused action"

      # Gone: the record is in the trash, so the service answers "This note
      # is gone" and writes nothing.
      if prepared.fetch(:answers_gone, true)
        Page.where(id: @page.id).update_all(trashed_at: Time.current)
        gone = capture_signals do
          result = run_case(prepared)
          assert_not result.ok?
          assert_not result.denied?
        end
        Page.where(id: @page.id).update_all(trashed_at: nil)
        assert_empty gone, "sent for an action on a record that is gone"
      end

      # For real, inside a transaction that then commits: nothing before the
      # commit, everything after it.
      signals = capture_signals do |seen|
        ActiveRecord::Base.transaction do
          assert run_case(prepared).ok?
          assert_empty seen, "sent before the outermost transaction committed"
        end
      end
      thread_ids |= Notes::Thread.where(container: @page).ids

      signals.each { |stream, payload| assert_ids_only(stream, payload) }
      on_record, on_people = signals.partition { |stream, _payload| stream == @record }
      on_inbox, on_people = on_people.partition { |_stream, payload| payload["kind"] == "inbox" }
      inboxes = prepared.fetch(:inbox, []).map { |user| [ Notes::Signals.person_stream(users(user).id), { "kind" => "inbox", "origin" => TAB } ] }
      assert_equal inboxes.sort, on_inbox.sort
      assert_equal prepared.fetch(:record), on_record.size
      on_record.each do |_stream, payload|
        assert_equal [ "threads", TAB ], payload.values_at("kind", "origin")
        assert_includes thread_ids, payload["thread_id"]
      end
      expected = prepared.fetch(:people).to_h { |user, reason| [ Notes::Signals.person_stream(users(user).id), reason ] }
      assert_equal expected, on_people.to_h { |stream, payload| [ stream, payload["reason"] ] }
      assert_equal expected.size, on_people.size
      on_people.each do |stream, payload|
        delivery = Notes::Delivery.find(payload["delivery_id"])
        assert_equal stream, Notes::Signals.person_stream(delivery.user_id)
        assert_equal delivery.reason, payload["reason"]
      end
    end
  end

  # The guard above looks at the notes services. Nothing else in the app may
  # broadcast at all: whatever is pushed goes through `Notes::Signals`, where
  # the payload is built.
  test "nothing in the app broadcasts but Live::Signals, and only a ...::Signals module calls it" do
    pattern = /\.broadcast\b|broadcast_to|broadcasts?_(to|refresh|append|prepend|replace|update|remove|render|action)|broadcast_stream|broadcaster|turbo_stream_from/
    found = Dir[Rails.root.join("{app,lib}/**/*.{rb,erb}")].select do |file|
      File.readlines(file).any? { |line| !line.strip.start_with?("#") && line.match?(pattern) }
    end

    assert_equal [ "app/models/live/signals.rb" ], found.map { |file| Pathname(file).relative_path_from(Rails.root).to_s }

    # The name is the convention, not a lock (any file could define such a
    # module): a domain's own `Signals` module says what the domain sends, and
    # sends through `Live::Signals.later`.
    callers = Dir[Rails.root.join("{app,lib}/**/*.rb")].select do |file|
      File.readlines(file).any? { |line| !line.strip.start_with?("#") && line.match?(/Live::Signals\.later\b/) }
    end
    callers.each do |file|
      assert_match(/^\s*module \w+::Signals\b|^\s*module Signals\b/, File.read(file), "#{file} calls Live::Signals.later but is not a Signals module") unless file.end_with?("app/models/live/signals.rb")
    end
  end

  test "a new note signals its record and the person it mentions" do
    thread = start

    assert_equal [ { "kind" => "threads", "thread_id" => thread.id } ], sent(@record)
    assert_equal [ { "kind" => "delivery", "delivery_id" => Notes::Delivery.find_by!(user: users(:reader)).id, "reason" => "mention" } ], sent(@reader)
    assert_empty sent(@two)
  end

  test "the tab that made the change is named by its opaque id, and a junk id is dropped" do
    Current.set(notes_tab: TAB) { start }
    assert_equal TAB, sent(@record).last["origin"]

    [ "<script>alert(1)</script>", "A secret sentence", "short", "x" * 41, "TAB-12345678", "tab-12345678\nmore", [ TAB ], nil, "" ].each do |junk|
      Current.set(notes_tab: junk) { start }
      assert_not sent(@record).last.key?("origin"), junk.inspect
    end
  end

  # Every broadcast of a whole thread's life, on every stream it touches.
  test "no signal ever holds anything but a kind, ids and a reason" do
    signals = capture_signals do
      thread = start
      as(users(:reader)) do
        reply = Notes::Reply.call(thread, body: "Another secret").record
        Notes::EditMessage.call(reply, body: "A reworded secret for @[#{users(:one).id}]")
        Notes::Resolve.call(thread)
        Notes::Reopen.call(thread)
        Notes::DeleteMessage.call(reply)
      end
      as(users(:two)) { Notes::Pin.call(thread); Notes::Unpin.call(thread) }
      Notes::Remove.call(@page)
    end

    signals.each { |stream, payload| assert_ids_only(stream, payload) }
    assert_equal 9, sent(@record).size # start, reply, edit, resolve, reopen, delete, pin, unpin, remove
    # start: reader (mention). reply: two. edit: one (mention), who follows
    # from then on. resolve: two and one. reopen: two and one. Then the
    # inboxes that got smaller: two's and one's (the deleted reply, which
    # told one and mentioned the other), and reader's, two's and one's (the
    # removed thread).
    assert_equal [ 7, 5 ], signals.reject { |stream, _| stream == @record }.partition { |_, payload| payload["kind"] == "delivery" }.map(&:size)
    assert_equal 12, signals.size - 9
    assert_equal signals.size, [ @record, @reader, @two, Notes::Signals.person_stream(users(:one).id) ].sum { |stream| sent(stream).size }
  end

  test "an action that changes nothing signals nobody" do
    thread = start
    as(users(:reader)) { Notes::Resolve.call(thread) }

    signals = capture_signals do
      as(users(:reader)) do
        assert Notes::Resolve.call(thread).ok?
        assert Notes::EditMessage.call(thread.first_message, body: " ").errors.any?
      end
      as(users(:two)) do
        assert Notes::EditMessage.call(thread.first_message, body: thread.first_message.body).ok?
        assert Notes::Unpin.call(thread).ok?
        assert Notes::Pin.call(thread).errors.any?
      end
      assert Notes::Remove.call(create_page(title: "No notes")).ok?
    end

    assert_empty signals
  end

  test "nothing is sent for an action that is rolled back" do
    assert_no_broadcasts(@record) do
      assert_no_broadcasts(@reader) do
        ActiveRecord::Base.transaction do
          start
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "a refused or failed action sends nothing" do
    signals = capture_signals do
      as(@stranger) { Notes::Start.call(@page, body: "Hi") }
      as(users(:two)) do
        Notes::Start.call(@page, body: " ")
        Notes::Start.call(@page, body: "For @[#{@stranger.id}]")
      end
    end

    assert_empty signals
  end

  # A thread whose block was deleted a moment ago, and a message loaded
  # before its thread went (`Notes::Authorization`, "A container that is
  # nil"): each answers "This note is gone", and tells nobody.
  test "a stale thread or message sends nothing" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    thread = start(block)
    message = thread.first_message
    Notes::Thread.where(id: thread.id).delete_all

    signals = capture_signals do
      as(users(:two)) do
        [ Notes::Reply.call(thread, body: "Late"), Notes::Resolve.call(thread), Notes::Pin.call(thread), Notes::EditMessage.call(message, body: "Late"),
          Notes::EditMessage.call(Notes::Message.new(body: "x"), body: "Late"), Notes::Start.call(ContentBlock.new, body: "Late"),
          Notes::React.call(message, emoji: "👍", on: true), Notes::React.call(Notes::Message.new(body: "x"), emoji: "👍", on: true) ].each do |result|
          assert_not result.ok?
          assert_not result.denied?
        end
        assert Notes::DeleteMessage.call(message).ok?
      end
    end

    assert_empty signals
  end

  # A reaction is for whoever has the thread open, and for nobody's inbox
  # (handoff "Reaction chip": reactions never go to the inbox): the record's
  # stream, given and taken back alike, and no person's -- not the author's,
  # not a follower's, not the mentioned.
  test "a reaction signals its record, given and taken back, and no person; one that changes nothing or is refused signals nobody" do
    thread = start
    threads = [ @record, { "kind" => "threads", "thread_id" => thread.id } ]

    as(users(:one)) do
      assert_no_difference -> { Notes::Delivery.count } do
        assert_equal [ threads ], capture_signals { assert Notes::React.call(thread.first_message, emoji: "👍", on: true).ok? }
        # Asked for again: nothing changed, nobody is told.
        assert_empty capture_signals { assert Notes::React.call(thread.first_message, emoji: "👍", on: true).ok? }
        assert_equal [ threads ], capture_signals { assert Notes::React.call(thread.first_message, emoji: "👍", on: false).ok? }
        assert_empty capture_signals { assert Notes::React.call(thread.first_message, emoji: "👍", on: false).ok? }
      end
      assert_empty capture_signals { assert_not Notes::React.call(thread.first_message, emoji: "a secret", on: true).ok? }
      # A resolved thread takes none: its own signal is Resolve's, and the refusal sends nothing.
      assert Notes::Resolve.call(thread).ok?
      assert_empty capture_signals { assert_not Notes::React.call(thread.first_message, emoji: "👍", on: true).ok? }
    end
  end

  test "following signals nobody; reading tells the reader's own tabs once per call that read something" do
    thread = start
    other = create_page(title: "Another secret", published: false)
    3.times { start(other) }
    inbox = [ @reader, { "kind" => "inbox" } ]

    following = capture_signals do
      as(users(:reader)) do
        Notes::SetFollowing.call(thread, following: false)
        Notes::SetFollowing.call(thread, following: true)
      end
    end
    assert_empty following

    as(users(:reader)) do
      assert_equal [ inbox ], capture_signals { Notes::MarkRead.call(thread: thread) }
      assert_empty capture_signals { Notes::MarkRead.call(thread: thread) }
      assert_empty capture_signals { Notes::MarkRead.call(container: @page) }
      # Three rows, one signal.
      assert_equal [ inbox ], capture_signals { Notes::MarkRead.call }
      assert_empty capture_signals { Notes::MarkRead.call }
    end
  end

  test "deleting a message tells each person whose inbox row went with it, once, and nobody when there was none" do
    thread = start
    reply = as(users(:reader)) { Notes::Reply.call(thread, body: "For @[#{users(:one).id}]") }.record
    quiet = as(users(:two)) { Notes::Reply.call(thread, body: "Nobody new") }.record
    Notes::Delivery.where(message: quiet).delete_all

    silent = capture_signals { as(users(:two)) { assert Notes::DeleteMessage.call(quiet).ok? } }
    assert_equal [ @record ], silent.map(&:first)

    signals = capture_signals { as(users(:reader)) { assert Notes::DeleteMessage.call(reply).ok? } }
    assert_equal [ [ Notes::Signals.person_stream(users(:one).id), { "kind" => "inbox" } ], [ @two, { "kind" => "inbox" } ] ].sort,
      signals.reject { |stream, _| stream == @record }.sort

    # The thread goes with its last message, and its reader's row with it.
    last = capture_signals { as(users(:two)) { assert Notes::DeleteMessage.call(thread.first_message).ok? } }
    assert_equal [ [ @reader, { "kind" => "inbox" } ], [ @record, { "kind" => "threads", "thread_id" => thread.id } ] ].sort_by(&:first), last.sort_by(&:first)
    assert_equal 0, Notes::Thread.count
  end

  # --- Notes::Remove, in each of its callers' cases --------------------------

  test "deleting a block signals its page, whose drawer is still open, when the delete commits" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    other = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    threads = [ start(block), start(block), start(other) ]

    signals = capture_signals do |seen|
      ActiveRecord::Base.transaction do
        assert as(users(:two)) { ContentBlocks::Destroy.call(block) }.ok?
        assert_empty seen
      end
    end

    # The page's drawer, and the reader, whose two rows on the block's
    # threads are gone: told once.
    assert_equal [ [ @record, { "kind" => "threads", "thread_id" => threads.first.id } ], [ @reader, { "kind" => "inbox" } ] ], signals
    assert_equal [ threads.last.id ], Notes::Thread.where(container: @page).ids
  end

  test "a block's delete that is rolled back signals nobody" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    start(block)

    signals = capture_signals do
      ActiveRecord::Base.transaction do
        assert as(users(:two)) { ContentBlocks::Destroy.call(block) }.ok?
        raise ActiveRecord::Rollback
      end
    end

    assert_empty signals
    assert_equal 1, Notes::Thread.where(container: @page).count
  end

  test "a section deleted with its blocks signals the page once; kept blocks keep their notes and signal nobody" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    inside = @page.content_blocks.create!(block_type: "rich_text", position: 0, section: section, section_column: 1)
    start(inside)

    kept = capture_signals do
      ActiveRecord::Base.transaction do
        assert as(users(:two)) { ContentBlocks::Destroy.call(section, keep_blocks: true) }.ok?
        raise ActiveRecord::Rollback
      end
    end
    assert_empty kept

    signals = capture_signals { assert as(users(:two)) { ContentBlocks::Destroy.call(section.reload) }.ok? }

    assert_equal [ @record, @reader ], signals.map(&:first)
    signals.each { |stream, payload| assert_ids_only(stream, payload) }
  end

  test "a purge signals each purged container's stream once, ids only" do
    child = create_page(title: "A secret child", parent: @page, published: false)
    block = child.content_blocks.create!(block_type: "rich_text", position: 0)
    post = create_post(title: "A secret post", published: false)
    asset = create_media_asset
    [ @page, child, block, block, post ].each { |subject| start(subject) }
    # The reader holds no library right, so nobody is mentioned on the image.
    assert as(users(:two)) { Notes::Start.call(asset, body: "A secret on an image") }.ok?
    [ @page, post, asset ].each { |record| assert as(users(:two)) { Trash::Move.call(record) }.ok? }

    signals = capture_signals do
      [ @page, post, asset ].each { |record| assert as(users(:two)) { Trash::Purge.call(record.reload) }.ok? }
    end

    streams = [ @record, Notes::Signals.record_stream("Page", child.id), Notes::Signals.record_stream("Post", post.id),
      Notes::Signals.record_stream("Media::Asset", asset.id) ]
    # The records, and the reader once per purge that took rows of theirs
    # (the page branch: four threads, one signal; the post).
    assert_equal (streams + [ @reader, @reader ]).sort, signals.map(&:first).sort
    assert_equal [ { "kind" => "inbox" } ], signals.select { |stream, _| stream == @reader }.map(&:last).uniq
    signals.each { |stream, payload| assert_ids_only(stream, payload) }
    assert_equal 0, Notes::Thread.count
  end

  # --- best effort -----------------------------------------------------------

  # The note is committed by the time the signal is sent: a cable that is
  # down must not turn that into an error, nor stop what else waits for the
  # same commit.
  test "a broadcast that fails is reported and the write stands" do
    broken = Class.new(ActionCable::SubscriptionAdapter::Test) { def broadcast(*) = raise(IOError, "the cable is down") }
    ActionCable.server.instance_variable_set(:@pubsub, broken.new(ActionCable.server)) # put back by ActionCable::TestHelper's teardown
    reported = []
    subscriber = Class.new { define_method(:report) { |error, **| reported << error.message } }.new
    Rails.error.subscribe(subscriber)
    after_signals = false
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    result = nil
    ActiveRecord::Base.transaction do
      result = as(users(:two)) { Notes::Start.call(@page, body: "For @[#{users(:reader).id}]") }
      ActiveRecord.after_all_transactions_commit { after_signals = true }
    end

    assert result.ok?
    assert_equal 1, Notes::Thread.where(container: @page).count
    assert_equal [ "the cable is down" ] * 2, reported
    # The log says that it happened and to which kind, never what the error
    # said (a driver's message can quote what it was sending) nor a payload.
    lines = log.string.lines.grep(/Live signal not sent/)
    assert_equal [ "Live signal not sent (delivery): IOError", "Live signal not sent (threads): IOError" ], lines.map(&:strip)
    assert_no_match(/cable is down|thread_id|delivery_id|\d/, lines.join)
    assert after_signals, "a failed signal stopped the callbacks queued behind it"
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
    Rails.logger.stop_broadcasting_to(logger) if logger
  end
end
