require "test_helper"

class Notes::StartTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def start(subject, as_user: users(:reader), **options)
    as(as_user) { Notes::Start.call(subject, **{ body: "Is this price right?" }.merge(options)) }
  end

  test "a reader starts a thread on a block: one thread, one message, filed under the page" do
    result = start(@block, quote: "  €49 a month  ", origin_view: "editor", origin_locale: "en")

    assert result.ok?, result.errors.to_sentence
    thread = result.record
    assert_equal [ @block, @page, "open", "€49 a month", users(:reader) ], [ thread.subject, thread.container, thread.state, thread.quote, thread.created_by ]
    assert_equal [ "Is this price right?" ], thread.messages.map(&:body)
    assert_equal users(:reader), thread.first_message.author
    assert_in_delta thread.first_message.created_at, thread.last_message_at, 1.second
  end

  test "a note writes nothing of the record it is on" do
    before = [ @page.reload.updated_at, @block.reload.updated_at, PublicSite::Version.current ]

    start(@block)

    assert_equal before, [ @page.reload.updated_at, @block.reload.updated_at, PublicSite::Version.current ]
  end

  test "the audit event is on the content record and holds no text" do
    result = start(@block, quote: "a secret quote", body: "a secret body")
    event = Audit::Event.order(:id).last

    assert_equal [ "note.started", "ContentBlock", @block.id, users(:reader).id ], [ event.action, event.subject_type, event.subject_id, event.user_id ]
    assert_equal({ "thread_id" => result.record.id, "message_id" => result.record.first_message.id }, event.metadata)
    assert_nil event.snapshot
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "a stranger is refused with the read key on the container, and nothing is written" do
    result = start(@block, as_user: @stranger)

    assert_predicate result, :denied?
    assert_equal 0, Notes::Thread.count
    event = Audit::Event.order(:id).last
    assert_equal [ "access.denied", "pages.read", "Page", @page.id ], [ event.action, event.metadata["permission"], event.subject_type, event.subject_id ]
  end

  test "an empty and an over-long body are refused with a sentence" do
    assert_equal [ "Write something first." ], start(@page, body: " \n ").errors
    assert_equal [ "A note can be at most 4,000 characters." ], start(@page, body: "x" * 4_001).errors
    assert_equal 0, Notes::Thread.count
  end

  # Review Focus 2.
  # The refusal names nobody and is the same sentence, once, whether the id
  # belongs to a user who can't read the page or to nobody: a forged
  # `@[1] @[2] ...` must not answer with names, emails or which ids exist.
  test "a mention of someone who may not read the record is refused, and tells nobody" do
    other = User.create!(email_address: "other@example.com", name: "Otto Other", password: "a-long-password-1")
    sentence = [ "Someone you mentioned can't see this page." ]

    result = start(@page, body: "Look, @[#{@stranger.id}]")
    assert_equal sentence, result.errors
    assert_not_predicate result, :denied?
    assert_equal sentence, start(@page, body: "Look, @[999999999]").errors
    assert_equal sentence, start(@page, body: "Look, @[#{@stranger.id}] @[#{other.id}] @[999999999] @[#{users(:two).id}]").errors
    assert_equal sentence, start(@block, body: "Look, @[#{other.id}]").errors
    assert_equal [ 0, 0 ], [ Notes::Thread.count, Notes::Delivery.count ]
  end

  test "the mention refusal is worded for a post and for an image, still naming nobody" do
    assert_equal [ "Someone you mentioned can't see this post." ], start(create_post(title: "News"), body: "@[#{@stranger.id}]").errors
    assert_equal [ "Someone you mentioned can't open the media library." ],
      start(create_media_asset, as_user: users(:two), body: "@[#{@stranger.id}]").errors
  end

  test "more than twenty mentions are refused before anyone is looked up" do
    tokens = ->(count) { Array.new(count) { |index| "@[#{900_000 + index}]" }.join(" ") }
    result = nil

    statements = capture_sql { result = start(@page, body: tokens.call(21)) }

    assert_equal [ "A note can mention at most 20 people." ], result.errors
    # The lookup of the mentioned is the one statement that reads users by a
    # list of ids (the actor's own row is read by its id alone).
    assert_empty statements.grep(/"users"\."id" IN \(/), "the mentioned ids were looked up"
    assert_equal 0, Notes::Thread.count
    # Twenty is allowed as far as the count goes: it reaches the access check.
    assert_equal [ "Someone you mentioned can't see this page." ], start(@page, body: tokens.call(20)).errors
    assert_not_empty capture_sql { start(@page, body: tokens.call(20)) }.grep(/"users"\."id" IN \(/)
  end

  test "a mention of a reader is delivered" do
    result = start(@page, as_user: users(:two), body: "Look, @[#{users(:reader).id}]")

    assert result.ok?
    assert_equal [ [ users(:reader).id, "mention", result.record.id ] ], Notes::Delivery.pluck(:user_id, :reason, :thread_id)
  end

  test "an unknown origin view and a language that is not enabled fall back" do
    thread = start(@page, origin_view: "carrier-pigeon", origin_locale: "xx").record

    assert_equal [ "editor", nil ], [ thread.origin_view, thread.origin_locale ]
  end

  test "the page's row is locked before the block is looked up and the thread written" do
    statements = capture_sql { start(@block) }
    lock = statements.index { |sql| sql.include?(%(FROM "pages")) && sql.include?("FOR UPDATE") }
    look = statements.each_index.find { |index| lock && index > lock && statements[index].include?(%(FROM "content_blocks")) }
    write = statements.index { |sql| sql.start_with?(%(INSERT INTO "note_threads")) }

    assert lock && look && write, statements.join("\n")
    assert_operator lock, :<, look
    assert_operator look, :<, write
  end

  test "a block deleted beside the note is an ordinary failure" do
    stale = ContentBlock.find(@block.id)
    @block.destroy!

    result = start(stale)

    assert_equal [ "This block was deleted." ], result.errors
    assert_equal 0, Notes::Thread.count
  end

  test "a page in the trash takes no new note" do
    @page.update!(trashed_at: Time.current)

    assert_equal [ "This page is in the trash or was deleted." ], start(@page, as_user: users(:one)).errors
  end

  test "a library image takes a note from a media.upload holder, and a stranger is refused for that right" do
    asset = create_media_asset

    assert start(asset, as_user: users(:two), origin_view: "media").ok?
    assert_predicate start(asset, as_user: @stranger), :denied?
    event = Audit::Event.order(:id).last
    assert_equal [ "media.upload", "Media::Asset", asset.id ], [ event.metadata["permission"], event.subject_type, event.subject_id ]
  end

  # `Notes::Authorization#mention_errors` reads only people who can sign in:
  # an invited person in a group that may read the page is still refused.
  test "a mention of an invited person is refused with the same sentence" do
    invited = invited_user("invited@example.com", groups: [ access_control_groups(:read_only) ])

    assert_equal [ "Someone you mentioned can't see this page." ], start(@page, body: "Look, @[#{invited.id}]").errors
    assert_equal 0, Notes::Thread.count
  end
end
