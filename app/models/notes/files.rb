module Notes
  # A note's files (notes spec D9, D15, §3.6): up to five, ten megabytes each,
  # stored with the message and not in the media library -- working material,
  # not content. They are fixed when the message is written: an edit changes
  # its text only.
  #
  # THE TYPE IS WHAT THE BYTES ARE. `Marcel::MimeType.for(io)` is asked with
  # neither the file's name nor the type the browser declared: both are the
  # uploader's to choose, and Marcel trusts either the moment the bytes alone
  # don't settle it (`Media::Asset#sniffed_content_type` has the long form of
  # this). An HTML page named `report.pdf` is HTML, an SVG named `logo.png`
  # is SVG, and neither is allowed.
  #
  # What Marcel answers, as `test/models/notes/files_test.rb` pins it:
  #
  # - Plain text and CSV have no signature: `application/octet-stream`, as for
  #   anything it can't place. Such a file is taken as text only when its
  #   bytes ARE text (valid UTF-8, no NUL or other control character but tab,
  #   newline and return). Text that starts with a byte order mark it does
  #   call `text/plain`. Either way the name then only picks the LABEL,
  #   `.csv` or text -- a spreadsheet's CSV export starts with that mark.
  # - That makes a file of markup with no `<!DOCTYPE` and no `<html>` text
  #   too (`<script>…</script>` alone has no signature either). It is stored
  #   as `text/plain` and is harmless as that: nothing but one of the four
  #   image types is ever answered inline (`Admin::NoteFilesController`).
  # - The Office formats of today are zip archives, told from any other zip
  #   by what the archive starts with (`[Content_Types].xml` and `word/`,
  #   `xl/` or `ppt/`); OpenDocument's by the `mimetype` entry the format
  #   puts first. A plain zip, a jar and an EPUB are `application/zip` or
  #   their own type, and refused. A macro-enabled Office file (`.docm`) has
  #   the same start as its plain twin and is taken as it: it is a download
  #   like every document here, never opened by CS Studio.
  # - Legacy Office formats (.doc, .xls, .ppt) share one container signature
  #   with files that are none of them, so they are left out.
  #
  # NOTHING HERE PARSES A FILE. No variant is made of an image and no analyzer
  # runs on one (`attach` stores the blob as already analyzed): the bytes of
  # someone who may only read a page are sniffed for their first few
  # kilobytes, stored, and sent back as they came.
  #
  # ITS OWN STORAGE SERVICE (`SERVICE`, `config/storage.yml`). Active
  # Storage's read routes are public to whoever holds a signed id
  # (`config/initializers/active_storage_access.rb`). No signed id or blob
  # URL of a note's file is ever rendered, and should one exist all the same,
  # those routes refuse a blob of this service by its name.
  module Files
    SERVICE = :notes
    MAX_COUNT = 5
    MAX_BYTES = 10.megabytes
    IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
    ALLOWED = {
      "image/png" => "PNG", "image/jpeg" => "JPEG", "image/gif" => "GIF", "image/webp" => "WEBP",
      "application/pdf" => "PDF", "text/plain" => "TXT", "text/csv" => "CSV",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "DOCX",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "XLSX",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "PPTX",
      "application/vnd.oasis.opendocument.text" => "ODT",
      "application/vnd.oasis.opendocument.spreadsheet" => "ODS",
      "application/vnd.oasis.opendocument.presentation" => "ODP"
    }.freeze
    TEXT_SAMPLE = 64.kilobytes
    NOT_TEXT = /[\x00-\x08\x0B\x0C\x0E-\x1F]/
    # How much of a file's name a refusal repeats: the name is the uploader's.
    NAME_SHOWN = 80

    module_function

    def image?(content_type) = IMAGE_TYPES.include?(content_type)

    # The allowed type the upload's bytes are, or nil.
    def type_of(upload)
      io = upload.tempfile
      io.rewind
      sniffed = Marcel::MimeType.for(io)
      io.rewind
      return sniffed if ALLOWED.key?(sniffed) && sniffed != "text/plain"
      return unless sniffed == "text/plain" || (sniffed == "application/octet-stream" && text?(io))

      File.extname(upload.original_filename.to_s).casecmp?(".csv") ? "text/csv" : "text/plain"
    ensure
      io&.rewind
    end

    def text?(io)
      sample = String.new(io.read(TEXT_SAMPLE).to_s, encoding: Encoding::UTF_8)
      # A sample that ends in the middle of a character is still text: up to
      # three bytes of a cut one are let go.
      3.times { sample = sample.byteslice(0, sample.bytesize - 1) unless sample.valid_encoding? } if sample.bytesize == TEXT_SAMPLE
      # In this order: asking a string that is not valid UTF-8 whether it
      # is blank raises.
      sample.valid_encoding? && sample.present? && !sample.match?(NOT_TEXT)
    end

    # One sentence per refused file, naming it; or the one about the count.
    def errors_for(uploads)
      uploads = Array(uploads)
      return [ I18n.t("admin.notes.errors.files.too_many", count: MAX_COUNT) ] if uploads.size > MAX_COUNT

      uploads.filter_map do |upload|
        name = upload.original_filename.to_s.truncate(NAME_SHOWN)
        if upload.tempfile.size > MAX_BYTES then I18n.t("admin.notes.errors.files.too_big", name: name)
        elsif type_of(upload).nil? then I18n.t("admin.notes.errors.files.type", name: name)
        end
      end
    end

    # Attaches each upload under the type its bytes are, never the declared
    # one (`identify: false`: Active Storage would otherwise ask Marcel again,
    # WITH the name). Call inside the message's transaction, after
    # `errors_for` was empty. The rows are written there; the bytes are
    # stored when that transaction commits (Active Storage's own after-commit
    # upload), so a note that is rolled back stores nothing.
    def attach(message, uploads)
      Array(uploads).each do |upload|
        upload.tempfile.rewind
        message.files.attach(io: upload.tempfile, filename: upload.original_filename.to_s, content_type: type_of(upload),
          identify: false, metadata: { analyzed: true })
      end
    end

    # Removes the files of `messages` (a relation) for good: called by
    # whatever is about to delete those messages, inside its transaction and
    # BEFORE the delete -- `Notes::Remove` deletes threads with one DELETE and
    # their messages by the foreign key, so no message callback ever runs
    # there, and the rows that say which files were theirs would be gone.
    #
    # The attachment rows and the blob rows go here, in the transaction. THE
    # STORED BYTES GO ONLY ONCE EVERY TRANSACTION OPEN NOW HAS COMMITTED
    # (`ActiveRecord.after_all_transactions_commit`, the discipline of
    # `Notes::Signals`): a file erased from storage cannot be brought back by
    # a rollback, and a purge that rolls back must find its notes' files
    # where they were. No job: there is no blob row left for one to find.
    #
    # Three statements whatever the number of files, one when there is none.
    # Erasing is best effort, like a signal: the rows are gone and committed,
    # and a storage that fails must not turn that into an error page -- the
    # log line names the error's class, never a file.
    def remove(messages)
      attachments = ActiveStorage::Attachment.where(record_type: Message.polymorphic_name, name: "files", record_id: messages.select(:id))
      blobs = ActiveStorage::Blob.where(id: attachments.select(:blob_id)).pluck(:id, :key, :service_name)
      return if blobs.empty?

      attachments.delete_all # version: none (a note's files; no public page reads one)
      ActiveStorage::Blob.where(id: blobs.map(&:first)).delete_all # version: none (a note's files; no public page reads one)
      ActiveRecord.after_all_transactions_commit { blobs.each { |_id, key, service| erase(key, service) } }
      nil
    end

    def erase(key, service)
      ActiveStorage::Blob.services.fetch(service).delete(key)
    rescue StandardError => error
      Rails.logger.warn("Notes file not erased: #{error.class}")
      Rails.error.report(error, handled: true)
    end
  end
end
