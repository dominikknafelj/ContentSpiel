require "zlib"

# Files for the notes tests (notes spec §3.6): uploads built from bytes, so a
# test says what a file IS apart from what it is called and what the browser
# declared, and the smallest real document of each allowed format.
#
# WHAT IS STORED IS TAKEN AWAY AGAIN. The rows go with the test's
# transaction; the bytes are in `tmp/storage/notes` (the test `notes`
# service), which no rollback reaches. `erase_note_files` deletes the files
# of every note blob there is at the end of the test, by key -- never the
# directory, which the other workers of a parallel run are using. A test that
# includes this module gets it as a teardown.
module NoteFilesHelper
  PDF = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b
  HTML = "<!DOCTYPE html><html><body><script>alert(1)</script></body></html>".freeze
  CONTENT_TYPES = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>'.freeze
  OFFICE = { "docx" => "word/document.xml", "xlsx" => "xl/workbook.xml", "pptx" => "ppt/presentation.xml" }.freeze
  OPEN_DOCUMENT = { "odt" => "text", "ods" => "spreadsheet", "odp" => "presentation" }.freeze

  def self.included(test)
    super
    test.setup { @note_file_keys = [] }
    test.teardown { erase_note_files }
  end

  # An upload as a controller hands it to a service: `content` under `name`,
  # declared by the browser as `declared`.
  def note_upload(content, name, declared = "application/octet-stream")
    file = Tempfile.new([ "note", File.extname(name) ], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, declared, true, original_filename: name)
  end

  def fixture_upload(fixture, name: fixture, declared: "application/octet-stream") = note_upload(file_fixture(fixture).binread, name, declared)

  # A zip archive with its entries stored, not compressed, in the order
  # given: what a format's signature is read from.
  def stored_zip(entries)
    local = "".b
    central = "".b
    entries.each do |name, data|
      data = data.b
      sizes = [ Zlib.crc32(data), data.bytesize, data.bytesize, name.bytesize ]
      offset = local.bytesize
      local << [ "PK\x03\x04".b, 20, 0, 0, 0, 0x21, *sizes, 0 ].pack("a4vvvvvVVVvv") << name.b << data
      central << [ "PK\x01\x02".b, 20, 20, 0, 0, 0, 0x21, *sizes, 0, 0, 0, 0, 0, offset ].pack("a4vvvvvvVVVvvvvvVV") << name.b
    end
    local + central + [ "PK\x05\x06".b, 0, 0, entries.size, entries.size, central.bytesize, local.bytesize, 0 ].pack("a4vvvvVVv")
  end

  # The smallest Word, Excel or PowerPoint file: the package's content types
  # first, then its one part.
  def office_bytes(extension) = stored_zip([ [ "[Content_Types].xml", CONTENT_TYPES ], [ "_rels/.rels", "<Relationships/>" ], [ OFFICE.fetch(extension), "<document/>" ] ])

  # The smallest OpenDocument file: its `mimetype` entry first, as the format asks.
  def open_document_bytes(extension) = stored_zip([ [ "mimetype", "application/vnd.oasis.opendocument.#{OPEN_DOCUMENT.fetch(extension)}" ], [ "content.xml", "<office/>" ] ])

  def note_blobs = ActiveStorage::Blob.where(service_name: Notes::Files::SERVICE.to_s)

  def note_service = ActiveStorage::Blob.services.fetch(Notes::Files::SERVICE)

  def stored?(key) = note_service.exist?(key)

  # Remembers the files there are now, to be erased at the end of the test
  # even when their rows are deleted before then; answers their keys.
  def note_file_keys = note_blobs.pluck(:key).tap { |keys| @note_file_keys |= keys }

  def erase_note_files
    (@note_file_keys | note_blobs.pluck(:key)).each { |key| note_service.delete(key) }
  end
end
