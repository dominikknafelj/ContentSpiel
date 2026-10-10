require "test_helper"
require "support/note_files_helper"

class Notes::RemoveTest < ActiveSupport::TestCase
  include NoteFilesHelper

  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @other = create_page(title: "Other")
    as(users(:two)) do
      Notes::Start.call(@page, body: "On the page, @[#{users(:reader).id}]")
      Notes::Start.call(@block, body: "On the block")
      Notes::Start.call(@other, body: "Elsewhere")
    end
    # A reaction on every message: it goes with its message (the foreign key).
    as(users(:reader)) { Notes::Message.find_each { |note| Notes::React.call(note, emoji: "👍", on: true) } }
  end

  def left = [ Notes::Thread.count, Notes::Message.count, Notes::Delivery.count, Notes::Follow.count, Notes::Reaction.count ]

  test "it removes the threads of the record and of what goes with it, and nothing else" do
    result = Notes::Remove.call(@page, with: [ @block ])

    assert result.ok?
    assert_equal [ @other ], Notes::Thread.all.map(&:subject)
    assert_equal [ 1, 1, 0, 1, 1 ], left
  end

  test "one event on the record, ids only; none when there was nothing to remove" do
    ids = Notes::Thread.where(container: @page).order(:id).pluck(:id)

    Notes::Remove.call(@page, with: [ @block ])

    event = Audit::Event.order(:id).last
    assert_equal [ "notes.removed", "Page", @page.id, nil ], [ event.action, event.subject_type, event.subject_id, event.snapshot ]
    assert_equal ids, event.metadata["thread_ids"].sort
    assert_no_difference -> { Audit::Event.count } do
      assert Notes::Remove.call(@page, with: [ @block ]).ok?
    end
  end

  test "it costs the same statements for one thread as for many" do
    one = capture_sql { Notes::Remove.call(@other) }.size
    as(users(:two)) do
      6.times do |index|
        note = Notes::Start.call(@block, body: "Note #{index}").record.first_message
        Notes::EMOJI.first(3).each { |emoji| Notes::React.call(note, emoji: emoji, on: true) }
      end
    end
    many = capture_sql { Notes::Remove.call(@page, with: [ @block ]) }.size

    assert_equal one, many
  end

  test "removing a record's notes removes their files, in the same number of statements for one file as for many" do
    file = -> { fixture_upload("tiny.png", name: "shot.png", declared: "image/png") }
    quiet = create_page(title: "One file", published: false)
    as(users(:two)) do
      Notes::Start.call(quiet, body: "One", files: [ file.call ])
      3.times { Notes::Start.call(@block, body: "Many", files: [ file.call, file.call ]) }
    end
    keys = note_file_keys

    one = capture_sql { Notes::Remove.call(quiet) }
    many = capture_sql { Notes::Remove.call(@page, with: [ @block ]) }

    assert_equal one.size, many.size
    assert_equal [ 1, 1 ], [ many.count { |sql| sql.start_with?('DELETE FROM "active_storage_attachments"') }, many.count { |sql| sql.start_with?('DELETE FROM "active_storage_blobs"') } ]
    # The files' rows go while the messages still say whose they are.
    assert_operator many.index { |sql| sql.start_with?('DELETE FROM "active_storage_blobs"') }, :<, many.index { |sql| sql.start_with?('DELETE FROM "note_threads"') }
    assert_equal [ 0, 0 ], [ ActiveStorage::Attachment.where(record_type: "Notes::Message").count, note_blobs.count ]
    assert_empty keys.select { |key| stored?(key) }
  end

  test "notes without files cost one read more and no delete of a file" do
    statements = capture_sql { Notes::Remove.call(@other) }

    assert_equal 1, statements.count { |sql| sql.include?('"active_storage_blobs"') }
    assert_empty statements.grep(/\ADELETE FROM "active_storage/)
  end

  test "a block's notes go with the right to edit its page; a reader is refused and nothing is removed" do
    refused = as(users(:reader)) { Notes::Remove.call(@block) }

    assert_predicate refused, :denied?
    assert_equal 3, Notes::Thread.count
    assert as(users(:two)) { Notes::Remove.call(@block) }.ok?
    assert_equal 2, Notes::Thread.count
  end
end
