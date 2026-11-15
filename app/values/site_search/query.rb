module SiteSearch
  # What a visitor asked, as every backend is handed it (spec §5.1): `text`
  # normalised (`normalise`), `language` the page's locale code, `page` from
  # 1 and `per_page` (`PER_PAGE`), and `now`, the visitor's view: a document
  # is in it when `shown_from <= now` and `shown_until` is nil or after
  # `now`. A text over `MAX_LENGTH` is never made a query (spec §8.3), so a
  # backend never meets one. `close_matches` (spec §7.1) is true for a
  # visitor's search, on which a backend may add close matches by its own
  # rule, and false for ContentSpiel's verifying search of a correction,
  # which a backend answers exact and stemmed matches only.
  Query = Data.define(:text, :language, :page, :per_page, :now, :close_matches)

  class Query
    MAX_LENGTH = 200
    PER_PAGE = 10

    MARKERS = /[\u{E000}\u{E001}]/
    CONTROL = /[[:cntrl:]]/

    def initialize(text:, language:, page:, per_page:, now:, close_matches: true) = super

    # `raw` as one line of words, or nil when nothing is left of it: nil for
    # anything but a String (`?q[]=a` is a parameter's Array). Invalid bytes,
    # the snippet's two marker characters (spec §6.4, which would land in the
    # marked text) and control characters are taken out after whitespace is
    # collapsed, so a newline between two words is a space and a NUL inside
    # one is nothing. The length is not cut here: the caller judges it on
    # what this answers.
    def self.normalise(raw)
      return nil unless raw.is_a?(String)

      text = raw.dup.force_encoding(Encoding::UTF_8).scrub("")
      text.squish.gsub(MARKERS, "").gsub(CONTROL, "").squish.presence
    end

    # The index of the page's first hit among them all.
    def offset = (page - 1) * per_page
  end
end
