require "test_helper"
require "support/note_files_helper"

class Notes::FilesTest < ActiveSupport::TestCase
  include NoteFilesHelper

  def type(content, name = "file") = Notes::Files.type_of(note_upload(content, name))

  def refused(name) = [ "#{name}: this type of file can't be attached." ]

  test "the type is what the bytes are" do
    assert_equal "image/png", Notes::Files.type_of(fixture_upload("tiny.png"))
    assert_equal "image/gif", Notes::Files.type_of(fixture_upload("small.gif"))
    assert_equal "application/pdf", type(PDF, "report.pdf")
    assert_equal "text/plain", type("Just some text.\nSecond line.\n", "notes.txt")
    assert_equal "text/csv", type("a,b\n1,2\n", "table.csv")
  end

  # What Marcel answers for these was never run when the plan was written:
  # each is asked here with the bytes of a real, smallest file of the format.
  test "plain text and CSV have no signature and are told by being text; a byte order mark is text too" do
    assert_equal "application/octet-stream", Marcel::MimeType.for(StringIO.new("Just some text.\n"))
    assert_equal "application/octet-stream", Marcel::MimeType.for(StringIO.new("a,b\n1,2\n"))
    assert_equal "text/plain", Marcel::MimeType.for(StringIO.new("\xEF\xBB\xBFa,b\n1,2\n".b))

    assert_equal "text/plain", type("Grüße aus Köln — ünïcödé\n", "notes")
    assert_equal "text/plain", type("a,b\n1,2\n", "table.txt") # the name only picks the label
    assert_equal "text/csv", type("\xEF\xBB\xBFa,b\n1,2\n".b, "export.CSV") # a spreadsheet's export
    assert_equal "text/plain", type("é" * 40_000, "long.txt") # the sample ends inside a character
    assert_nil type("", "empty.txt")
    assert_nil type("text\x00with a NUL".b, "odd.txt")
    assert_nil type("caf\xE9 in Latin-1".b, "latin.txt") # text, but not UTF-8: not taken
    assert_equal "text/plain", type("\xFF\xFEh\x00i\x00".b, "utf16.txt") # by its byte order mark
  end

  test "the Office and OpenDocument formats of today are told from their archives" do
    types = Notes::Files::ALLOWED.invert
    NoteFilesHelper::OFFICE.each_key { |extension| assert_equal types.fetch(extension.upcase), type(office_bytes(extension), "file.bin"), extension }
    NoteFilesHelper::OPEN_DOCUMENT.each_key { |extension| assert_equal types.fetch(extension.upcase), type(open_document_bytes(extension), "file.bin"), extension }
  end

  test "a zip that is no document is refused under a document's name, and so are the legacy Office formats" do
    page_in_a_zip = stored_zip([ [ "index.html", HTML ], [ "word/document.xml", "<document/>" ] ])
    jar = stored_zip([ [ "META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n" ] ])
    epub = stored_zip([ [ "mimetype", "application/epub+zip" ] ])
    legacy = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00".b * 600)

    { "report.docx" => page_in_a_zip, "sheet.xlsx" => jar, "slides.odp" => epub, "letter.doc" => legacy, "archive.zip" => page_in_a_zip }.each do |name, bytes|
      declared = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      assert_equal refused(name), Notes::Files.errors_for([ note_upload(bytes, name, declared) ]), name
    end
  end

  # Review Focus 5.
  test "a file is refused by what it is, whatever it is called and whatever the browser said" do
    assert_equal refused("report.pdf"), Notes::Files.errors_for([ note_upload(HTML, "report.pdf", "application/pdf") ])
    assert_equal refused("page.docx"), Notes::Files.errors_for([ note_upload("<html><body>Hello</body></html>", "page.docx") ])
    assert_equal refused("logo.png"), Notes::Files.errors_for([ fixture_upload("tiny.svg", name: "logo.png", declared: "image/png") ])
    assert_equal refused("drawing.txt"), Notes::Files.errors_for([ note_upload('<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>', "drawing.txt", "text/plain") ])
    assert_equal refused("tool.txt"), Notes::Files.errors_for([ note_upload("MZ\x90\x00\x03\x00\x00\x00".b + ("\x00".b * 64), "tool.txt", "text/plain") ])
    assert_equal refused("run.txt"), Notes::Files.errors_for([ note_upload("#!/bin/sh\necho hi\n", "run.txt", "text/plain") ])
    assert_empty Notes::Files.errors_for([ note_upload(PDF, "page.html", "text/html") ]) # a PDF, whatever its name
  end

  # Markup with no signature is text to Marcel and to this: it is stored as
  # `text/plain`, never as what its name or the browser says, and only an
  # image is ever answered inline (`test/integration/admin/note_files_test.rb`).
  test "markup without a signature is plain text, whatever it is called" do
    assert_equal "text/plain", Notes::Files.type_of(note_upload("<script>alert(1)</script>", "page.html", "text/html"))
    assert_equal "text/plain", Notes::Files.type_of(note_upload("<img src=x onerror=alert(1)>", "logo.png", "image/png"))
  end

  test "five files at most, ten megabytes each" do
    six = Array.new(6) { |index| note_upload("text #{index}", "f#{index}.txt") }
    assert_equal [ "A note can carry at most 5 files." ], Notes::Files.errors_for(six)

    big = note_upload("a" * (10.megabytes + 1), "big.txt")
    assert_equal [ "big.txt: files can be at most 10 MB." ], Notes::Files.errors_for([ big ])
    assert_empty Notes::Files.errors_for([ note_upload("a" * 10.megabytes, "full.txt") ])
    assert_empty Notes::Files.errors_for([])
  end

  test "a refusal repeats at most eighty characters of a file's name" do
    error = Notes::Files.errors_for([ note_upload(HTML, "#{"long" * 40}.pdf") ]).sole

    assert_operator error.length, :<, 130
  end
end
