module SiteSearch
  # What the suggestions while typing come to (search 2 spec §4.1, §4.3):
  # `state` `:ok` or `:unavailable` (`STATES`), and `items`, up to
  # `SUGGEST_LIMIT` `Item`s, the titles first, then the tags.
  #
  # An `Item` is plain text and ranges, never markup: `kind` `:page`,
  # `:post` or `:tag`; `label` a title as published in the language, or a
  # tag's current name; `where` a page's place (the titles above it, the
  # homepage first, joined by `PLACE_SEPARATOR`, nil for the homepage and a
  # page under nothing), a post's date in `DATE_FORMAT`, nil for a tag;
  # `url` the address it goes to; `marks` `[start, length]` ranges on
  # `label` (`marks_of`), computed here and never taken from an engine.
  SuggestAnswer = Data.define(:state, :items)

  class SuggestAnswer
    STATES = %i[ok unavailable].freeze

    Item = Data.define(:kind, :label, :where, :url, :marks)

    # A result's place and date as the Search block writes them
    # (`Blocks::SearchComponent::Result`, which a model does not name;
    # test/models/site_search/suggest_test.rb holds the two equal).
    PLACE_SEPARATOR = " › ".freeze
    DATE_FORMAT = "%-d %b %Y".freeze

    WORD = /[\p{L}\p{M}\p{N}]+/

    # ContentSpiel's part of an answer: the backend's `titles`
    # (`SiteSearch::Suggestion`s) re-checked as hits are (`Shown`), so the
    # label, the place and the address are read from the copy in force and
    # `public_paths`; the tags (`TagSuggestions`); a tag's address, its
    # listing page (`TagPage`) or else a search for it on the site's search
    # page (`SearchPage`), a tag with neither left out, both read in one
    # pass (`TagPage.with_search_page`). Up to
    # `TITLE_SUGGESTIONS` titles and `TAG_SUGGESTIONS` tags, each kind
    # filling the other's gap up to `SUGGEST_LIMIT`.
    #
    # ONE TRANSACTION, rolled back after, under a `SET LOCAL
    # statement_timeout` of what is left before `deadline`, so its
    # statements end with it; with nothing left, nothing is asked and it
    # raises. THE STATEMENTS are a constant number, whatever the count of
    # titles and tags: the `SET LOCAL`, `Shown`'s, one for the tags, and,
    # when there is a tag, `TagPage.with_search_page`'s and the addresses'
    # (test/models/site_search/suggest_test.rb holds the ceiling,
    # `SUGGEST_STATEMENTS`).
    def self.build(prefix:, titles:, language:, now:, deadline:)
      timeout = Postgres::Query.timeout_in_ms(deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC))
      raise ActiveRecord::QueryCanceled, "the suggestion's deadline passed before the database was asked" unless timeout

      answer = nil
      ApplicationRecord.transaction(requires_new: true) do
        # sql: Arel has no node for SET; the value is an Integer, and `.to_i` says so to Brakeman
        ApplicationRecord.connection.execute("SET LOCAL statement_timeout = #{timeout.to_i}") # version: none (a setting of the suggestion's own transaction, which writes nothing)
        answer = new(state: :ok, items: items_for(prefix, titles, language, now))
        raise ActiveRecord::Rollback
      end
      answer
    end

    # `[start, length]` ranges on `label` where the prefix is: for each word
    # of the prefix, the start of each word of the label that begins with
    # it, case-folded, as long as the prefix's word (the longest when
    # several begin one word); in a `LIMITED` language, every place the
    # label contains the prefix, case aside. Sorted, never overlapping.
    def self.marks_of(label, prefix, limited:)
      marks = limited ? contained(label, prefix) : begun(label, prefix.scan(WORD))
      marks.sort.each_with_object([]) { |mark, kept| kept << mark if kept.empty? || mark[0] >= kept.last.sum }
    end

    def self.begun(label, words)
      label.enum_for(:scan, WORD).filter_map do
        word = Regexp.last_match
        length = words.select { |each| word[0][0, each.length].casecmp?(each) }.map(&:length).max
        [ word.begin(0), length ] if length
      end
    end

    def self.contained(label, prefix)
      finder = /#{Regexp.escape(prefix)}/i
      label.enum_for(:scan, finder).map { [ Regexp.last_match.begin(0), Regexp.last_match[0].length ] }
    end

    def self.items_for(prefix, titles, language, now)
      limited = Postgres::LIMITED.include?(language)
      hits = titles.map do |title|
        Hit.new(record_type: title.record_type, record_id: title.record_id, copy_id: title.copy_id, language: language, snippet: nil, rank: title.rank)
      end
      shown = Shown.for(Results.new(hits: hits, total: hits.size), locale: language, now: now)
      tags = tag_items(TagSuggestions.new(text: prefix, language: language, now: now, limit: SUGGEST_LIMIT).tags, language, now)
      tag_count = [ tags.size, [ TAG_SUGGESTIONS, SUGGEST_LIMIT - shown.size ].max ].min
      title_items = shown.first(SUGGEST_LIMIT - tag_count).map { |item| title_item(item) }
      (title_items + tags.first(tag_count)).map { |item| item.with(marks: marks_of(item.label, prefix, limited: limited)) }
    end

    def self.title_item(item)
      where = item.kind == :page ? item.where&.join(PLACE_SEPARATOR) : item.date&.strftime(DATE_FORMAT)
      Item.new(kind: item.kind, label: item.title, where: where, url: item.url_path, marks: [])
    end

    # Each tag with its address, the ones with none left out: its listing
    # page, else a search for its name on the site's search page.
    def self.tag_items(tags, language, now)
      return [] if tags.empty?

      listings, search = TagPage.with_search_page(tags.map(&:id), locale: language, now: now)
      urls = PublicSite::Urls.new.prefetch([ *listings.values, search ].compact, language)
      search_path = urls.path_for(search, language) if search
      tags.filter_map do |tag|
        url = listings[tag.id] ? urls.path_for(listings[tag.id], language) : (search_path && "#{search_path}?#{{ q: tag.name }.to_query}")
        Item.new(kind: :tag, label: tag.name, where: nil, url: url, marks: []) if url
      end
    end

    private_class_method :begun, :contained, :items_for, :title_item, :tag_items
  end
end
