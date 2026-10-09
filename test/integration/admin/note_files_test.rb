require "test_helper"
require "support/note_files_helper"

# A note's files over HTTP (notes spec D14, D15, §3.6): sent with the message
# as one multipart post, and read through one action only.
class Admin::NoteFilesTest < ActionDispatch::IntegrationTest
  include NoteFilesHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @base = "/cs-studio/notes/page/#{@page.id}"
    files = [ fixture_upload("tiny.png", name: "shot.png", declared: "image/png"), note_upload(PDF, "report.pdf", "application/pdf"),
      fixture_upload("small.gif", name: "loop.gif", declared: "image/gif") ]
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Three files", files: files) }.record
    @note = @thread.first_message
    @image, @pdf, @gif = %w[shot.png report.pdf loop.gif].map { |name| @note.files.attachments.find { |attachment| attachment.filename.to_s == name } }
  end

  def frame = { "Turbo-Frame" => "notes" }

  def file_path(attachment, thread: @thread, note: @note, base: @base) = "#{base}/threads/#{thread.id}/messages/#{note.id}/files/#{attachment.id}"

  test "a note is sent with files as one multipart post, and a reply too" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "With a picture", files: [ fixture_file_upload("tiny.png", "image/png") ] }

    assert_response :see_other
    assert_equal [ "tiny.png" ], Notes::Thread.order(:id).last.first_message.files.map { |file| file.filename.to_s }

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "And a reply", files: [ "", fixture_file_upload("small.gif", "text/plain") ] }

    assert_response :see_other
    assert_equal [ "image/gif" ], @thread.messages.reload.last.files.map(&:content_type)
  end

  # `files[]` is a file field's: anything else a request puts there is not a file.
  test "what is sent as files and is no upload is not taken for one" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Forged", files: [ "a string", { "tempfile" => "/etc/passwd", "original_filename" => "x.txt" } ] }

    assert_response :see_other
    assert_empty Notes::Thread.order(:id).last.first_message.files
  end

  test "an image is shown inline through the notes action, a document is a download, and no Active Storage URL is rendered" do
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-message-#{@note.id} > [data-note-files]" do
      assert_select "a[data-note-image][target=_blank][href='#{file_path(@image)}'] img[src='#{file_path(@image)}'][alt='shot.png']"
      assert_select "a[data-note-file][href='#{file_path(@pdf)}']", text: /report\.pdf\s*PDF · \d+ Bytes/
      assert_select "[data-note-gif] a[target=_blank][href='#{file_path(@gif)}'] img[src='#{file_path(@gif)}'][alt='loop.gif']"
      assert_select "[data-note-gif]", text: /GIF · loop\.gif/
      assert_select "[data-note-gif] button", text: "Play"
    end
    assert_no_active_storage_url(response.body)
  end

  # Decision D15: no read URL of Active Storage's, no blob key and no signed
  # id of a note's file is written into a page, in any view that draws notes.
  test "no rendered view of the notes holds an Active Storage URL: the list, the composer, a thread being edited, the resolved" do
    sign_in_as(users(:two))

    [ @base, "#{@base}?compose=Page-#{@page.id}", "#{@base}/threads/#{@thread.id}?edit=#{@note.id}", "#{@base}/threads/#{@thread.id}?delete=#{@note.id}",
      "/cs-studio/pages/#{@page.id}", "/cs-studio/notes" ].each do |path|
      get path
      assert_response :ok, path
      assert_no_active_storage_url(response.body, path)
    end
    assert_select "#note-message-#{@note.id} [data-note-files]", count: 0 # the last page read draws no thread

    as(users(:two)) { Notes::Resolve.call(@thread) }
    get "#{@base}/resolved", headers: frame
    assert_no_active_storage_url(response.body)
    post "#{@base}/threads", params: { body: "", files: [ fixture_file_upload("tiny.svg", "image/png") ] }, headers: frame
    assert_no_active_storage_url(response.body)
  end

  # The pinned cost of the thread view (Task 16): ONE read more than before
  # files, for the attachments of all its messages with their blobs joined
  # in -- whatever the number of messages and of files. The list reads none.
  test "the thread view reads its files in one statement, with three files on one message or eleven on eight" do
    sign_in_as(users(:reader))
    path = "#{@base}/threads/#{@thread.id}"
    get path, headers: frame
    one = capture_sql { get path, headers: frame }
    assert_equal 1, one.grep(/"active_storage_attachments"/).size
    assert_equal 1, one.grep(/"active_storage_blobs"/).size # the same statement: a join

    7.times do |index|
      files = index.even? ? [ fixture_upload("tiny.png"), note_upload(PDF, "report-#{index}.pdf") ] : []
      as(users(:two)) { Notes::Reply.call(@thread, body: "Reply #{index}", files: files) }
    end
    get path, headers: frame # reads what the replies delivered

    many = capture_sql { get path, headers: frame }
    assert_select "[data-note-files]", count: 5
    assert_select "[data-note-files] a[data-note-file], [data-note-files] a[data-note-image], [data-note-files] [data-note-gif]", count: 11
    assert_equal one.size, many.size
    assert_equal [ 1, 1 ], [ many.grep(/"active_storage_attachments"/).size, many.grep(/"active_storage_blobs"/).size ]

    assert_empty capture_sql { get @base, headers: frame }.grep(/active_storage/)
  end

  test "an edit form is drawn without a file field, and the message's files stay under it" do
    sign_in_as(users(:two))

    get "#{@base}/threads/#{@thread.id}?edit=#{@note.id}", headers: frame

    assert_select "#note-message-#{@note.id} form[data-note-composer] input[type=file]", count: 0
    assert_select "#note-message-#{@note.id} form[data-note-composer]:not([enctype])"
    assert_select "#note-message-#{@note.id} > [data-note-files] a[data-note-file]"
    assert_select "[data-note-part=reply] form[data-note-composer][enctype='multipart/form-data'] input[type=file][name='files[]'][multiple]"
  end

  test "the headers: nosniff always, inline for an image only and under its stored type, never stored by a cache" do
    sign_in_as(users(:reader))

    get file_path(@image)
    assert_response :ok
    assert_equal [ "image/png", "nosniff" ], [ response.media_type, response.headers["X-Content-Type-Options"] ]
    assert_match(/\Ainline; filename="shot\.png"/, response.headers["Content-Disposition"])
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal file_fixture("tiny.png").binread, response.body

    get file_path(@gif)
    assert_equal "image/gif", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])

    get file_path(@pdf)
    assert_equal "application/pdf", response.media_type
    assert_match(/\Aattachment; filename="report\.pdf"/, response.headers["Content-Disposition"])
    assert_equal [ "nosniff", "private, no-store" ], response.headers.values_at("X-Content-Type-Options", "Cache-Control")
    assert_equal PDF, response.body
  end

  # The type sent is the one stored, which was read from the bytes -- never
  # one the request names, and never one outside the allowed list.
  test "nothing in a request changes the type or the disposition, and a stored type that is not allowed is a plain download" do
    sign_in_as(users(:reader))

    get file_path(@pdf), params: { disposition: "inline", content_type: "text/html", format: "html" }, headers: { "Accept" => "text/html" }
    assert_equal "application/pdf", response.media_type
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])

    # A row someone wrote around `Notes::Files` (it never stores such a type).
    @image.blob.update_columns(content_type: "text/html") # version: none (a note's file; no public page reads one)
    get file_path(@image)
    assert_equal [ "application/octet-stream", "nosniff" ], [ response.media_type, response.headers["X-Content-Type-Options"] ]
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])

    @gif.blob.update_columns(content_type: "image/svg+xml") # version: none (as above)
    get file_path(@gif)
    assert_equal "application/octet-stream", response.media_type
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  end

  test "text that is markup is a download of plain text" do
    script = note_upload("<script>alert(1)</script>", "page.html", "text/html")
    reply = as(users(:two)) { Notes::Reply.call(@thread, body: "Markup", files: [ script ]) }.record
    sign_in_as(users(:reader))

    get file_path(reply.files.attachments.sole, note: reply)

    assert_equal [ "text/plain", "nosniff" ], [ response.media_type, response.headers["X-Content-Type-Options"] ]
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  end

  test "a file is found only as an attachment of that message of that thread of this record, by someone who may read it" do
    other = create_page(title: "Other")
    elsewhere = as(users(:two)) { Notes::Start.call(other, body: "Elsewhere", files: [ fixture_upload("tiny.png") ]) }.record
    reply = as(users(:two)) { Notes::Reply.call(@thread, body: "A reply", files: [ fixture_upload("tiny.png") ]) }.record
    second = as(users(:two)) { Notes::Start.call(@page, body: "A second thread") }.record
    logo = create_media_asset.file.attachment

    sign_in_as(users(:reader))
    get file_path(@image)
    assert_response :ok
    # A real file of a note of ANOTHER RECORD, under this record's address and under its own thread's.
    get file_path(elsewhere.first_message.files.attachments.sole)
    assert_response :not_found
    get file_path(@image, base: "/cs-studio/notes/page/#{other.id}")
    assert_response :not_found
    get file_path(@image, base: "/cs-studio/notes/page/#{other.id}", thread: elsewhere, note: elsewhere.first_message)
    assert_response :not_found
    # A real file of ANOTHER MESSAGE of the same thread, and this message under another thread.
    get file_path(reply.files.attachments.sole)
    assert_response :not_found
    get file_path(@image, thread: second)
    assert_response :not_found
    get file_path(@image, note: reply)
    assert_response :not_found
    # A real attachment, but a library image's; and nothing but an id is an id.
    get file_path(logo)
    assert_response :not_found
    [ @image.blob.key, @image.blob.signed_id, @image.blob.id + 1_000_000 ].each do |id|
      get "#{@base}/threads/#{@thread.id}/messages/#{@note.id}/files/#{id}"
      assert_response :not_found
    end
  end

  test "a stranger, a signed-out visitor and anyone once the page is in the trash get nothing" do
    get file_path(@image)
    assert_response :redirect
    assert_no_match(/PNG/, response.body)

    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))
    get file_path(@image)
    assert_response :not_found

    @page.update!(trashed_at: Time.current)
    sign_in_as(users(:one))
    get file_path(@image)
    assert_response :not_found
  end

  test "an image's note files need the media right: forbidden without it, as its notes are" do
    asset = create_media_asset
    thread = as(users(:two)) { Notes::Start.call(asset, body: "On the image", files: [ fixture_upload("tiny.png") ]) }.record
    path = file_path(thread.first_message.files.attachments.sole, thread: thread, note: thread.first_message, base: "/cs-studio/notes/media/#{asset.id}")

    sign_in_as(users(:two))
    get path
    assert_response :ok

    sign_in_as(users(:reader))
    get path
    assert_response :forbidden

    # In the trash the image is not found, for someone who has the right too.
    assert Trash::Move.call(asset).ok?
    sign_in_as(users(:two))
    get path
    assert_response :not_found
  end

  test "a file whose bytes are gone from storage is not found, not an error page" do
    sign_in_as(users(:reader))
    note_file_keys
    note_service.delete(@image.blob.key)

    get file_path(@image)

    assert_response :not_found
  end

  test "a refused file re-renders the form with the text kept and the file and the reason named" do
    sign_in_as(users(:reader))

    assert_no_difference [ -> { Notes::Thread.count }, -> { ActiveStorage::Blob.count } ] do
      post "#{@base}/threads", params: { body: "Keep this text", files: [ fixture_file_upload("tiny.svg", "image/png") ] }, headers: frame
    end

    assert_response :unprocessable_entity
    assert_select "#notes-new [role=alert]", text: /tiny\.svg: this type of file can't be attached\./
    assert_select "#notes-new textarea[name=body]", text: "Keep this text"
    assert_select "#notes-new [role=alert]", text: /Attach the files again/
    assert_select "#notes-new [role=alert][class~='text-danger-ink'][class~='text-[12px]']"
  end

  test "a refused reply keeps its text in the reply field and says the same; a refusal without files does not mention them" do
    sign_in_as(users(:reader))

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "Keep this reply", files: [ fixture_file_upload("tiny.svg", "image/png") ] }, headers: frame

    assert_response :unprocessable_entity
    assert_select "[data-note-part=reply] [role=alert]", text: /tiny\.svg: this type of file can't be attached\..*Attach the files again/m
    assert_select "[data-note-part=reply] textarea[name=body]", text: "Keep this reply"

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "x" * 4_001 }, headers: frame
    assert_response :unprocessable_entity
    assert_select "[data-note-part=reply] [role=alert]", text: /at most 4,000/
    assert_no_match(/Attach the files again/, response.body)
  end

  # Decision D14: a note's file names reach no log. Rails logs an uploaded
  # file with its original name and its part's headers; the notes controllers'
  # parameters are filtered (`config/initializers/filter_parameter_logging.rb`).
  test "an uploaded file's name is filtered from the request's logged parameters, and the upload itself is untouched" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "With a secret file", files: [ fixture_file_upload("tiny.png", "image/png"), fixture_file_upload("small.gif", "image/gif") ] }

    assert_response :see_other
    logged = request.filtered_parameters["files"]
    assert_equal 2, logged.size
    assert_equal [ "[FILTERED]" ], logged.map(&:original_filename).uniq
    assert_no_match(/tiny|small\.gif|form-data/, request.filtered_parameters.inspect)
    assert_equal %w[tiny.png small.gif], Notes::Thread.order(:id).last.first_message.files.map { |file| file.filename.to_s } # the log's copy only

    post "#{@base}/threads/#{@thread.id}/messages", params: { body: "A reply", files: [ fixture_file_upload("tiny.png", "image/png") ] }
    assert_no_match(/tiny|form-data/, request.filtered_parameters.inspect)
  end

  test "an upload to another controller is logged as before" do
    sign_in_as(users(:two))

    post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }

    assert_match(/tiny\.png/, request.filtered_parameters.inspect)
  end

  # --- Active Storage's own read routes (they stay public for the site's images) ---

  test "Active Storage's public routes refuse a note's blob, by signed id and by a disk key, and still serve a library image" do
    blob = @image.blob
    signed = blob.signed_id
    disk_key = ActiveStorage.verifier.generate({ key: blob.key, disposition: "inline", content_type: "image/png", service_name: "notes" }, purpose: :blob_key)

    [ "/rails/active_storage/blobs/redirect/#{signed}/shot.png", "/rails/active_storage/blobs/proxy/#{signed}/shot.png",
      "/rails/active_storage/blobs/#{signed}/shot.png", "/rails/active_storage/disk/#{disk_key}/shot.png" ].each do |path|
      get path
      assert_response :not_found, path
      assert_not_includes response.body.b, file_fixture("tiny.png").binread, path
    end
    variation = ActiveStorage::Variation.encode(resize_to_limit: [ 10, 10 ])
    %w[redirect proxy].each do |kind|
      get "/rails/active_storage/representations/#{kind}/#{signed}/#{variation}/shot.png"
      assert_response :not_found, kind
    end
    # Refused before anything was read: no variant was made or stored.
    assert_equal 0, ActiveStorage::VariantRecord.count
    assert_equal 3, Dir.glob("#{note_service.root}/**/*").count { |file| @note.files.blobs.any? { |blob| file.include?(blob.key) } }

    library = create_media_asset.file.blob
    get "/rails/active_storage/blobs/redirect/#{library.signed_id}/tiny.png"
    assert_response :redirect
    get response.location
    assert_response :ok
    assert_equal file_fixture("tiny.png").binread, response.body
  end

  private

  def assert_no_active_storage_url(body, where = nil)
    assert_no_match "/rails/active_storage", body, where
    @note.files.blobs.each do |blob|
      assert_no_match blob.key, body, where
      assert_no_match blob.signed_id, body, where
    end
  end
end
