module Dashboard
  # The dashboard's "Needs translation" card: for every target language, how
  # the viewer's readable pages, posts and (for a `media.upload` holder)
  # images stand -- `{ total:, complete:, missing:, outdated: }` in items,
  # straight from `Translations::StateIndex.summaries` over the same
  # read-scoped relations the Translations overview lists (kept records
  # only), never worked out per record -- plus the most recently changed
  # *outdated* item, the one the editor most likely wants to review first.
  #
  # The queries scale with the number of languages and model types, never
  # with the number of records: one `StateIndex.summaries` for every language
  # at once (two grouped queries per type) and, per language, one `LIMIT 1`
  # per type for the outdated item -- an inner join on the state, so a
  # language with nothing outdated costs an index lookup, not a scan.
  #
  # Empty (so the card is hidden) with one language -- there is nothing to
  # translate into -- and when the viewer can read nothing at all.
  class TranslationNeeds
    # `item` is `[type, record]` (type "page", "post" or "media") or nil.
    Entry = Data.define(:locale, :name, :total, :complete, :missing, :outdated, :item)

    def initialize(actor:, channel: Current.channel)
      @actor = actor
      @channel = channel
    end

    def entries
      @entries ||= begin
        relations = readable
        if relations.empty?
          []
        else
          locales = Translations.target_locales
          summaries = Translations::StateIndex.summaries(locales, relations.values)
          locales.map { |locale| entry(locale, relations, summaries.fetch(locale.to_s)) }
        end
      end
    end

    private

    # `{ "page" => relation, ... }` -- only the types the viewer can read.
    def readable
      {
        "page" => AccessControl.scope(@actor, "pages.read", Page.all, channel: @channel),
        "post" => AccessControl.scope(@actor, "posts.read", Post.all, channel: @channel),
        "media" => (Media::Asset.kept if AccessControl.holds?(@actor, "media.upload", channel: @channel))
      }.compact.select { |type, _| type == "media" || AccessControl.holds?(@actor, "#{type}s.read", channel: @channel) }
    end

    def entry(locale, relations, summary)
      summary = summary.slice(:total, :complete, :missing, :outdated)
      newest = relations.filter_map do |type, relation|
        record = Translations::StateIndex.joins(relation, locale:, states: "outdated")
          .reorder(updated_at: :desc, id: :desc).first
        [ type, record ] if record
      end.max_by { |_, record| [ record.updated_at, record.id ] }
      Entry.new(locale:, name: Locales.name(locale, native: true), item: newest, **summary)
    end
  end
end
