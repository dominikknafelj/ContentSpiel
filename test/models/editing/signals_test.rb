require "test_helper"

class Editing::SignalsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @page = create_page(title: "Pricing", published: false)
    # An image block: its caption is a plain translated column a save can change.
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @stream = Editing::Signals.record_stream(@page)
  end

  def sent(stream = @stream) = broadcasts(stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  def only_new(stream = @stream)
    before = sent(stream).size
    yield
    sent(stream).drop(before)
  end

  test "every action the app records is mapped or silent, with a reason, and none is both" do
    known = Editing::Signals::MAP.keys + Editing::Signals::SILENT.keys
    assert_empty Audit::Sentence::ACTIONS - known, "content event names Editing::Signals does not know: map each to a reason, or list it in SILENT with why"
    assert_empty known - Audit::Sentence::ACTIONS, "Editing::Signals names actions nothing records"
    assert_empty Editing::Signals::MAP.keys & Editing::Signals::SILENT.keys
    Editing::Signals::SILENT.each { |action, why| assert_operator why.length, :>, 20, "#{action} needs its reason" }
    assert_empty Editing::Signals::MAP.values.uniq - %w[saved structure gone]
  end

  test "an action no list knows is reported and sends nothing" do
    event = Audit::Event.new(action: "block.exploded", subject_type: "ContentBlock", subject_id: @block.id)
    reported = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, **| reported << error } }.new)

    assert_empty only_new { Editing::Signals.heard(event) }
    assert_equal 1, reported.size
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "a block's save signals its page: content, saved, the block's id and nothing else" do
    signals = only_new { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? }

    assert_equal [ { "kind" => "content", "content_block_id" => @block.id, "reason" => "saved" } ], signals
  end

  test "a save coalesced into an open event signals again" do
    assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "one" } }).ok?
    signals = only_new { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "two" } }).ok? }

    assert_equal 1, signals.size
  end

  test "an added, duplicated, reordered and deleted block each signal structure, with no block id" do
    added = only_new { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }) }
    copied = only_new { assert ContentBlocks::Duplicate.call(@block).ok? }
    ids = @page.content_blocks.reload.top_level.reorder(:position, :id).ids
    moved = only_new { assert ContentBlocks::Reorder.call(@page, ids.reverse).ok? }
    deleted = only_new { assert ContentBlocks::Destroy.call(@block).ok? }

    structure = { "kind" => "content", "content_block_id" => nil, "reason" => "structure" }
    [ added, moved, deleted ].each { |signals| assert_equal [ structure ], signals }
    # A copy is a block.created and then the block.reordered that puts it after its source.
    assert_equal [ structure, structure ], copied
  end

  test "a section's fold signals structure" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "three" } }).record
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 3 })
    signals = only_new do
      assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }).ok?
    end

    assert_equal %w[structure], signals.map { |signal| signal["reason"] }
  end

  test "a plain save of a section after its fold is a save with the block's id, not a structure" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "three" } }).record
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 3 })
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }).ok?
    signals = only_new { assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two", "background" => "tinted" } }).ok? }

    assert_equal [ { "kind" => "content", "content_block_id" => section.id, "reason" => "saved" } ], signals
  end

  test "trashing a branch tells the editor of each child page too" do
    child = create_page(title: "Child", parent: @page, published: false)
    assert_equal %w[gone], only_new(Editing::Signals.record_stream(child)) { assert Trash::Move.call(@page).ok? }.map { |signal| signal["reason"] }
  end

  test "the page's own save signals saved with no block, and a post's its post" do
    page_signals = only_new { assert Pages::Save.call(@page, translations: { "en" => { subtitle: "s" } }).ok? }
    post = create_post(title: "News", published: false)
    post_signals = only_new(Editing::Signals.record_stream(post)) { assert Posts::Save.call(post, translations: { "en" => { excerpt: "e" } }).ok? }

    assert_equal [ { "kind" => "content", "content_block_id" => nil, "reason" => "saved" } ], page_signals
    assert_equal [ { "kind" => "content", "content_block_id" => nil, "reason" => "saved" } ], post_signals
  end

  test "trashing a page signals gone" do
    assert_equal %w[gone], only_new { assert Trash::Move.call(@page).ok? }.map { |signal| signal["reason"] }
  end

  test "the tab that made the change is named, and a junk id is left out" do
    named = Current.set(editing_tab: "tab-12345678") { only_new { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "a" } }) } }
    junk = Current.set(editing_tab: "<script>") { only_new { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "b" } }) } }

    assert_equal "tab-12345678", named.sole["origin"]
    assert_not junk.sole.key?("origin")
  end

  test "nothing is sent for a write that is rolled back, and a signal that fails does not fail the write" do
    rolled = only_new do
      ActiveRecord::Base.transaction do
        ContentBlocks::Save.call(@block, translations: { "en" => { caption: "gone" } })
        raise ActiveRecord::Rollback
      end
    end
    assert_empty rolled

    with_singleton_override(Live::Signals, :later, ->(*) { raise "the cable is away" }) do
      assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "kept" } }).ok?
    end
    assert_equal "kept", @block.reload.caption
  end

  test "a note, a sign-in, a library image's save and a removal of notes signal nothing on the page's stream" do
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "media.updated", subject_type: "Media::Asset", subject_id: @page.id)) }
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "notes.removed", subject_type: "Page", subject_id: @page.id)) }
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "note.started", subject_type: "Page", subject_id: @page.id)) }
    assert_empty only_new { Editing::Signals.heard(Audit::Event.new(action: "session.created")) }
  end
end
