module SiteSearch
  # The words of a document shown under a hit (spec §5.1): `text` plain
  # text, and `marks` the `[start, length]` ranges of `text`, in
  # characters, that matched the query. Ranges and never markup, so the
  # backend hands the page nothing it would have to trust: ContentSpiel
  # escapes the text and draws the marks itself (spec §6.4).
  Snippet = Data.define(:text, :marks)
end
