# The public site's search (search spec). A published copy becomes words in
# one place, `SiteSearch::Documents`, as plain `SiteSearch::Document`s that
# every backend indexes alike.
module SiteSearch
  # The most characters a document's field holds (spec §4.2): Postgres
  # refuses a tsvector over 1 MB and counts word positions only to 16,383,
  # and a page of tables or of Code blocks would pass either inside the
  # publish that indexes it. Words past the cut are not found.
  MAX_TEXT = 200_000

  # How long a backend has to answer a visitor's search (spec §5.7), in
  # seconds: its deadline is this from the moment `search` asks, on the
  # monotonic clock.
  TIMEOUT = 3

  # What `search` answers when the backend raised, passed its deadline or
  # answered after it: the block then says search is unavailable, and the
  # page is drawn as any page, with its status 200.
  UNAVAILABLE = :unavailable

  # The most characters of a hit's snippet the page draws (spec §5.1: "a
  # few words around the match"). An outside engine's highlighter can hand
  # back a whole field; the built-in's `ts_headline` stays far under it.
  SNIPPET_LENGTH = 500

  module_function

  # The one caller of a backend's `search` (spec §5.7): the chosen backend's
  # `SiteSearch::Results` for `query`, or `UNAVAILABLE`. Nothing it meets
  # raises out of it. A failure is reported through `SiteSearch::Reports`
  # (at most once a minute) as a `SiteSearch::Unavailable`, the backend's
  # name and the error's class, and is scrubbed to that inside the
  # `search.query` span, which is never handed an error: the exception event
  # a span writes holds the error's message, and an engine's message holds
  # the address it asked, which holds the query. The span records the
  # backend, the outcome, the total and the page, and never the query (spec
  # §9).
  def search(query)
    backend = Backends.current_name
    Telemetry.in_span("search.query", attributes: { "search.backend" => backend, "search.page" => query.page }) do |span|
      answer = ask(query, backend)
      Telemetry.record(span, "search.outcome" => outcome_of(answer), "search.results" => answer == UNAVAILABLE ? 0 : answer.total)
      answer
    end
  end

  # The backend's answer, or `UNAVAILABLE` with the failure reported. An
  # answer handed back after the deadline is a failure too: a backend that
  # does not watch its deadline is late all the same. So is an answer of
  # the wrong shape (`checked`), inside the scrubbed path, since the page
  # would otherwise raise on it while drawing, a 500; and every snippet is
  # cut to `SNIPPET_LENGTH`.
  def ask(query, backend)
    Unavailable.scrubbing(backend: backend) do
      deadline = clock + TIMEOUT
      results = Backends.current.search(query, deadline: deadline)
      raise Timeout::Error if clock > deadline

      cut_snippets(checked(results))
    end
  rescue Unavailable => error
    Reports.report(backend: backend, error: error)
    UNAVAILABLE
  end

  # `results` when it is what the contract says (`SiteSearch::Results`, an
  # Integer total, an Array of `SiteSearch::Hit`s with Integer ids, each
  # snippet nil or plain text with `[start, length]` pairs of Integers);
  # raises `TypeError` otherwise, which the caller scrubs to its class.
  def checked(results)
    raise TypeError, "a search backend answers SiteSearch::Results" unless results.is_a?(Results)
    raise TypeError, "a total is an Integer" unless results.total.is_a?(Integer)
    raise TypeError, "hits are an Array" unless results.hits.is_a?(Array)

    results.hits.each do |hit|
      raise TypeError, "a hit is a SiteSearch::Hit with Integer ids" unless hit.is_a?(Hit) && hit.record_id.is_a?(Integer) && hit.copy_id.is_a?(Integer)
      raise TypeError, "a snippet is plain text with pairs of Integers" unless hit.snippet.nil? || snippet?(hit.snippet)
    end
    results
  end

  def snippet?(snippet)
    snippet.is_a?(Snippet) && snippet.text.is_a?(String) && snippet.marks.is_a?(Array) &&
      snippet.marks.all? { |mark| mark.is_a?(Array) && mark.size == 2 && mark.all?(Integer) }
  end

  def cut_snippets(results)
    hits = results.hits.map { |hit| hit.snippet ? hit.with(snippet: cut_snippet(hit.snippet)) : hit }
    results.with(hits: hits)
  end

  # `snippet` cut to `SNIPPET_LENGTH` characters at the last whitespace
  # before the cut, as `cut` cuts a field, with the marks that end past the
  # cut dropped; a snippet within it is answered as it is.
  def cut_snippet(snippet)
    return snippet if snippet.text.length <= SNIPPET_LENGTH

    head = snippet.text[0, SNIPPET_LENGTH]
    unless snippet.text[SNIPPET_LENGTH].match?(/\s/)
      space = head.rindex(/\s/)
      head = head[0, space] if space
    end
    head = head.rstrip
    Snippet.new(text: head, marks: snippet.marks.select { |start, length| start + length <= head.length })
  end

  def outcome_of(answer)
    return "unavailable" if answer == UNAVAILABLE

    answer.total.zero? ? "none" : "results"
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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

  private_class_method :ask, :checked, :snippet?, :cut_snippets, :outcome_of, :clock
end
