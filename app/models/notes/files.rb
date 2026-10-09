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
  #   bytes ARE text: valid UTF-8, no NUL or other control character but tab,
  #   newline and return.
  # - Text that starts with a byte order mark it calls `text/plain` whatever
  #   follows, so `<html>` or `<svg>` behind a mark would pass as text. A
  #   UTF-8 mark is therefore taken off and what follows is asked again: it
  #   is refused as the markup it is. Text in UTF-16 is not UTF-8 and is
  #   refused with the sentence that says so, like a Latin-1 CSV.
  # - The Office formats of today are zip archives, told from any other zip
  #   by what the archive starts with (`[Content_Types].xml` and `word/`,
  #   `xl/` or `ppt/`); OpenDocument's by the `mimetype` entry the format
  #   puts first. A plain zip, a jar and an EPUB are `application/zip` or
  #   their own type, and refused.
  # - Legacy Office formats (.doc, .xls, .ppt) share one container signature
  #   with files that are none of them, so they are left out.
  #
  # AND THE NAME MUST AGREE WITH THE TYPE (`EXTENSIONS`). The bytes decide
  # what a file is stored and served as, but a person who downloads it gets
  # it under its NAME, and their machine opens it by that name's ending. So
  # a file is refused when its name does not end in one of the endings of
  # the type its bytes are -- none at all included. That is what keeps out
  # what the sniff alone lets through: markup with no signature
  # (`<body onload=…>`) or a script named `.html`, `.hta`, `.ps1` or `.cmd`,
  # which is text and may only be called `.txt`, `.md`, `.log` or `.csv`; a
  # macro-enabled Word file (`.docm`), whose bytes start like a `.docx`; a
  # picture named `.txt`. The refusal says which endings the type may have.
  # For text the ending also picks the type: `.csv` is `text/csv`.
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
    # The endings a file of each type may have (lower case, no dot).
    EXTENSIONS = {
      "image/png" => %w[png], "image/jpeg" => %w[jpg jpeg], "image/gif" => %w[gif], "image/webp" => %w[webp],
      "application/pdf" => %w[pdf], "text/plain" => %w[txt md log], "text/csv" => %w[csv],
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => %w[docx],
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => %w[xlsx],
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => %w[pptx],
      "application/vnd.oasis.opendocument.text" => %w[odt],
      "application/vnd.oasis.opendocument.spreadsheet" => %w[ods],
      "application/vnd.oasis.opendocument.presentation" => %w[odp]
    }.freeze
    TEXT_TYPES = %w[text/plain text/csv].freeze
    TEXT_EXTENSIONS = EXTENSIONS.values_at(*TEXT_TYPES).flatten.freeze
    TEXT_SAMPLE = 64.kilobytes
    NOT_TEXT = /[\x00-\x08\x0B\x0C\x0E-\x1F]/
    UTF8_MARK = "\xEF\xBB\xBF".b.freeze
    # How much of a file's name a refusal repeats: the name is the uploader's.
    NAME_SHOWN = 80
    # How long a stored name may be, its ending included.
    MAX_NAME = 255

    # What `examine` found: the type to store the file under, or why not --
    # `:type` (not an allowed kind of file), `:encoding` (text by its name,
    # but not UTF-8), `:ending` (an allowed kind under a name that is not
    # that kind's; `type` then says which kind).
    Verdict = Data.define(:type, :problem) do
      def ok? = problem.nil?
    end

    module_function

    def image?(content_type) = IMAGE_TYPES.include?(content_type)

    # The allowed type the upload may be stored under, or nil.
    def type_of(upload) = examine(upload).then { |verdict| verdict.type if verdict.ok? }

    def examine(upload)
      extension = extension_of(upload.original_filename)
      kind = kind_of_bytes(upload.tempfile)
      return Verdict.new(nil, :encoding) if kind == :not_utf8 && TEXT_EXTENSIONS.include?(extension)
      return Verdict.new(nil, :type) unless kind.is_a?(String)

      # Text is one kind with two types; its ending says which.
      type = kind == "text/plain" && extension == "csv" ? "text/csv" : kind
      endings = kind == "text/plain" ? TEXT_EXTENSIONS : EXTENSIONS.fetch(type)
      Verdict.new(type, (:ending unless endings.include?(extension)))
    ensure
      upload.tempfile.rewind
    end

    # What the bytes are: an allowed type, "text/plain" for text of either
    # text type, `:not_utf8` for what may be text in another encoding (no
    # signature, or a UTF-16 mark), nil for anything else.
    def kind_of_bytes(io)
      io.rewind
      sniffed = Marcel::MimeType.for(io)
      io.rewind
      return sniffed if ALLOWED.key?(sniffed) && !TEXT_TYPES.include?(sniffed)
      return unless [ "text/plain", "application/octet-stream" ].include?(sniffed)

      sample = io.read(TEXT_SAMPLE).to_s.b
      if sample.start_with?(UTF8_MARK)
        sample = sample.byteslice(UTF8_MARK.bytesize..)
        # Behind the mark: markup is markup, and so is anything else with a signature.
        return unless Marcel::MimeType.for(StringIO.new(sample)) == "application/octet-stream"
      elsif sniffed == "text/plain"
        return :not_utf8 # a UTF-16 or UTF-32 mark
      end
      text?(sample) ? "text/plain" : :not_utf8
    end

    def text?(bytes)
      sample = String.new(bytes, encoding: Encoding::UTF_8)
      # A sample that ends in the middle of a character is still text: up to
      # three bytes of a cut one are let go.
      3.times { sample = sample.byteslice(0, sample.bytesize - 1) unless sample.valid_encoding? } if bytes.bytesize >= TEXT_SAMPLE - UTF8_MARK.bytesize
      # In this order: asking a string that is not valid UTF-8 whether it
      # is blank raises.
      sample.valid_encoding? && sample.present? && !sample.match?(NOT_TEXT)
    end

    # The name's ending, lower case, without its dot; "" when it has none.
    def extension_of(name) = File.extname(stored_name(name)).delete_prefix(".").downcase

    # The name a file is stored and served under: Active Storage's own
    # sanitising, and no longer than `MAX_NAME` with its ending kept.
    # A NUL byte is taken out first: the sanitising leaves it in, and
    # `File.extname` raises on one ("path name contains null byte"), which
    # made a forged multipart part a 500.
    def stored_name(name)
      name = ActiveStorage::Filename.new(name.to_s.delete("\0")).sanitized
      return name if name.length <= MAX_NAME

      ending = File.extname(name).first(20)
      name.first(MAX_NAME - ending.length) + ending
    end

    # One sentence per refused file, naming it; or the one about the count.
    def errors_for(uploads)
      uploads = Array(uploads)
      return [ I18n.t("admin.notes.errors.files.too_many", count: MAX_COUNT) ] if uploads.size > MAX_COUNT

      uploads.filter_map do |upload|
        name = upload.original_filename.to_s.truncate(NAME_SHOWN)
        next I18n.t("admin.notes.errors.files.too_big", name: name, size: max_size) if upload.tempfile.size > MAX_BYTES

        verdict = examine(upload)
        case verdict.problem
        when :type then I18n.t("admin.notes.errors.files.type", name: name)
        when :encoding then I18n.t("admin.notes.errors.files.encoding", name: name)
        when :ending then I18n.t("admin.notes.errors.files.ending", name: name, kind: kind_label(verdict.type), endings: endings_of(verdict.type))
        end
      end
    end

    # "10 MB": the limit as a person reads it, from the constant.
    def max_size = ActiveSupport::NumberHelper.number_to_human_size(MAX_BYTES)

    def kind_label(type) = TEXT_TYPES.include?(type) ? I18n.t("admin.notes.errors.files.text") : ALLOWED.fetch(type)

    # ".txt, .md, .log or .csv"
    def endings_of(type)
      endings = (TEXT_TYPES.include?(type) ? TEXT_EXTENSIONS : EXTENSIONS.fetch(type)).map { |ending| ".#{ending}" }
      endings.to_sentence(two_words_connector: I18n.t("admin.notes.errors.files.or"), last_word_connector: I18n.t("admin.notes.errors.files.or"))
    end

    # Attaches each upload under the type its bytes are, never the declared
    # one (`identify: false`: Active Storage would otherwise ask Marcel again,
    # WITH the name). Call inside the message's transaction, after
    # `errors_for` was empty. The rows are written there; the bytes are
    # stored when that transaction commits (Active Storage's own after-commit
    # upload), so a note that is rolled back stores nothing.
    #
    # True when every file was attached. `attach` answers false when the save
    # behind it failed, and nothing may be left half written then: the caller
    # rolls its transaction back and answers `not_stored`.
    def attach(message, uploads)
      Array(uploads).all? do |upload|
        upload.tempfile.rewind
        message.files.attach(io: upload.tempfile, filename: stored_name(upload.original_filename), content_type: type_of(upload),
          identify: false, metadata: { analyzed: true })
      end
    end

    def not_stored = I18n.t("admin.notes.errors.files.not_stored")

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
