module SiteSearch
  # One published copy of a page or a post in one language, as words (spec
  # §4.1): a plain value, so a backend outside the CMS needs none of its
  # models. Built by `SiteSearch::Documents` alone.
  #
  # `key` is "Page:12:345:de" (record type, record id, copy id, language);
  # `url` the record's public path in that language when the document was
  # made, for an outside engine's display only (the built-in backend links
  # by `public_paths` at query time); `shown_from` the later of the copy's
  # `live_at` and the record's `published_at`; `shown_until` the `live_at`
  # of the copy scheduled to replace it, or nil. `text` is the body field's
  # text again, which a snippet is cut from, held to `MAX_TEXT` like every
  # field.
  Document = Data.define(:key, :record_type, :record_id, :copy_id, :language, :url, :live_at, :shown_from, :shown_until, :fields, :text)

  class Document
    def initialize(text:, **rest)
      super(text: SiteSearch.cut(text.to_s), **rest)
    end
  end
end
