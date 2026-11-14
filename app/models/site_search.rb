# The public site's search (search spec). A published copy becomes words in
# one place, `SiteSearch::Documents`, as plain `SiteSearch::Document`s that
# every backend indexes alike.
module SiteSearch
  # The most characters a document's field holds (spec §4.2): Postgres
  # refuses a tsvector over 1 MB and counts word positions only to 16,383,
  # and a page of tables or of Code blocks would pass either inside the
  # publish that indexes it. Words past the cut are not found.
  MAX_TEXT = 200_000

  module_function

  # `text` cut to MAX_TEXT characters at the last whitespace before the cut,
  # so no word is indexed half; a single word longer than the cut is cut
  # where it stands.
  def cut(text)
    return text if text.length <= MAX_TEXT
    return text[0, MAX_TEXT] if text[MAX_TEXT].match?(/\s/)

    head = text[0, MAX_TEXT]
    space = head.rindex(/\s/)
    space ? head[0, space].rstrip : head
  end

  # A rich-text document's paragraphs as search text: its plain paragraphs,
  # one per table cell, without the placeholders that stand for an image, a
  # video or a rule ("[image]"), which are no words of the page.
  def paragraphs(document) = document.plain_paragraphs - RichText::Document::PLAIN_PLACEHOLDERS.values
end
