module SiteSearch
  # The one place a published copy becomes words (spec §4): a page's or a
  # post's copy, rebuilt read-only (`Publishing::Snapshot.rebuild`), read
  # with the public readers, one `SiteSearch::Document` per enabled
  # language, each field through that language's fallback chain, so a
  # Spanish visitor finds a page by the English title the Spanish page
  # shows. Never the rows: words typed and not published are in no document.
  #
  # The fields, always all of them for the record's kind, blank or not:
  # `title` (A); `summary` (B), a page's subtitle and meta description, a
  # post's excerpt; `tags` (B, a post's), the tag names its copy shows;
  # `body` (C), a post's rich text and its type's translated string and
  # text fields, then every block's text in the copy's reading order
  # (`BlockTypeDefinition#search_text`); `code` (D), the Code blocks' code.
  module Documents
    # Moves when what a document holds for the same copy changes (a field,
    # a reader, a block type's text), so a backend can tell an index made
    # by older rules (spec §6.6).
    REVISION = 1

    MARKERS = /[\u{E000}\u{E001}]/
    CONTROL = /[[:cntrl:]]/

    module_function

    # One document per enabled language for `version`, a copy of its record.
    def for(version, now:, pending: :unknown)
      record = version.record
      pending = Publishing.pending(record, now: now) if pending == :unknown
      view = Publishing::Snapshot.rebuild(version, record)
      paths = PublicSite::Urls.new.paths_by_language(record)
      shown_from = [ version.live_at, record.published_at ].compact.max
      shown_until = pending.live_at if pending && pending.id != version.id && pending.live_at > version.live_at

      Locales.enabled.map do |locale|
        fields = fields_of(view, locale)
        Document.new(
          key: [ record.class.polymorphic_name, record.id, version.id, locale ].join(":"),
          record_type: record.class.polymorphic_name, record_id: record.id, copy_id: version.id, language: locale,
          url: paths[locale], live_at: version.live_at, shown_from: shown_from, shown_until: shown_until,
          fields: fields, text: fields.find { |field| field.name == "body" }.text
        )
      end
    end

    # The documents of what the site shows of `record` now and what it is
    # scheduled to show: its copy in force's and its pending copy's. None for
    # a record in the trash or neither published nor scheduled.
    def for_record(record, now:)
      return [] if record.trashed? || record.published_at.nil?

      pending = Publishing.pending(record, now: now)
      [ Publishing.current(record, now: now), pending ].compact.flat_map { |version| self.for(version, now: now, pending: pending) }
    end

    # `text` as one line of plain words: invalid bytes, markup, the snippet's
    # two marker characters (spec §6.4) and control characters taken out,
    # whitespace collapsed.
    def plain(text)
      text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
      text = Loofah.html5_fragment(text).text(encode_special_chars: false) if text.include?("<") || text.include?("&")
      text.gsub(MARKERS, "").gsub(CONTROL, " ").squish
    end

    def fields_of(view, locale)
      blocks = view.is_a?(Page) ? view.content_blocks.to_a : []
      fields = [
        Field.new(name: "title", weight: :a, text: plain(Locales.read(view, :title, locale: locale))),
        Field.new(name: "summary", weight: :b, text: joined(summary_of(view, locale)))
      ]
      fields << Field.new(name: "tags", weight: :b, text: joined(view.tags.map(&:name))) if view.is_a?(Post)
      fields << Field.new(name: "body", weight: :c, text: joined(post_text(view, locale) + block_texts(blocks, :body, locale)))
      fields << Field.new(name: "code", weight: :d, text: joined(block_texts(blocks, :code, locale)))
    end
    private_class_method :fields_of

    def summary_of(view, locale)
      names = view.is_a?(Page) ? %i[subtitle meta_description] : %i[excerpt]
      names.map { |name| Locales.read(view, name, locale: locale) }
    end
    private_class_method :summary_of

    # A post's body and the translated prose of its type's fields (a type
    # answers `translatable` for prose, the string and the text: not a code,
    # a date or a choice), each through the fallback chain.
    def post_text(view, locale)
      return [] unless view.is_a?(Post)

      fields = view.fields(locale: locale, fallback: true)
      prose = view.definition&.fields.to_a.select { |field| field.translated? && field.field_type&.translatable }
      words = prose.map { |field| fields.public_send(field.name) }
      SiteSearch.paragraphs(Locales.read(view, :body, locale: locale)) + words
    end
    private_class_method :post_text

    def block_texts(blocks, kind, locale)
      blocks.flat_map do |block|
        callable = block.definition&.search_texts&.dig(kind)
        callable ? Array(callable.call(block, locale: locale)) : []
      end
    end
    private_class_method :block_texts

    def joined(texts) = texts.map { |text| plain(text) }.reject(&:empty?).join(" ")
    private_class_method :joined
  end
end
