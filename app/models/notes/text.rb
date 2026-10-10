module Notes
  # A message body as parts, for a component to render (data here, markup
  # there: the dependency order). Plain text stays text -- the component
  # escapes it -- a mention token is the user's id, and a bare `http(s)` URL
  # is a link. Nothing else is recognised: no Markdown, no HTML.
  #
  # A link is offered only for what `RichText::BuiltIns.safe_href?` accepts,
  # the one rule for a URL an editor typed; the pattern already admits only
  # http and https. Punctuation that ends a sentence is not part of the URL.
  module Text
    Part = Data.define(:kind, :value)

    URL = %r{https?://[^\s<>"']+}
    PATTERN = Regexp.union(Mentions::TOKEN, URL)
    TRAILING = /[.,;:!?)\]]+\z/

    def self.parts(body)
      text = body.to_s
      parts = []
      position = 0
      text.scan(PATTERN) do
        match = Regexp.last_match
        from = match.begin(0)
        if match[0].start_with?("@[")
          part = Part.new(:mention, match[1].to_i)
          finish = match.end(0)
        else
          url = match[0].sub(TRAILING, "")
          next unless RichText::BuiltIns.safe_href?(url)

          part = Part.new(:link, url)
          finish = from + url.length
        end
        parts << Part.new(:text, text[position...from]) if from > position
        parts << part
        position = finish
      end
      parts << Part.new(:text, text[position..]) if position < text.length
      parts
    end
  end
end
