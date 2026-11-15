module BlockTypes
  # A search field for the visitors of a page, and for a request with `?q=`
  # what the site holds of the words (search spec §7.1). Placed on any page:
  # no address is reserved, the page tree owns every path, and the field
  # searches the page it stands on.
  #
  # WHERE EACH VALUE LIVES. The one value is the field's label, translated
  # (`translated_settings`), optional: blank draws the CMS's own word,
  # `public.blocks.search.label`. So no column, no migration and no service.
  #
  # `:search` is what hands the block the request's search: `PublicPageRendering
  # #search_answer`, run the first time a block that claims it asks and kept
  # for the render, so two Search blocks on a page search once and a page
  # without one never searches. A type from outside may not claim it
  # (`BlockTypeDefinition#refuse_outside!`): only this component is handed
  # the answer. Code asks `capability?(:search)`, never the type's name.
  #
  # It declares no `search_text`: the block is a field, not content
  # (`test/models/site_search/block_text_test.rb`, `NO_TEXT`).
  module Search
    # The label is one line above a field.
    LABEL_LENGTH = 80

    # The tile's line: "Searches the live site", after "Default label · "
    # where the label is blank. A blank label is a finished block, so the
    # line never says Empty.
    def self.summary(block, locale:)
      live = [ :hint, :searches_live ]
      label(block, locale: locale) ? [ live ] : [ [ :hint, :default_label ], [ :text, " · " ], live ]
    end

    # The tile's heading: the label in the language shown, or, blank, the
    # visitor's word in that language standing quiet; the line under it. So
    # there is always a preview.
    def self.preview(block, locale:)
      label = label(block, locale: locale)
      ContentModel::Preview.new(heading: label || PublicStrings.read("public.blocks.search.label", locale: locale),
                                quiet_heading: label.nil?, line: true)
    end

    # The label a visitor of `locale` reads: the language's own, else along
    # the site's fallback, as the public component reads it, so a tile says
    # "Default label" only where the page draws the CMS's word.
    def self.label(block, locale:) = block.settings_object(locale: locale, fallback: true)&.label.presence

    def self.register
      BlockTypes.register :search do |t|
        t.label "Search"
        t.icon "search", family: :form
        # A blank label draws the visitor's word, so the card shows that
        # word as the placeholder in the language being edited and the help
        # line names it (the Design System's EditorSearchBlock).
        t.field :label, :string, translated: true, max: LABEL_LENGTH,
                placeholder_public: "blocks.search.label", help: :"search.label_help"
        # Only the live site is searched, and in the preview too: a person
        # placing the block on a draft learns here that drafts are never found.
        t.editor_note :"search.note"
        t.summary ->(block, locale:) { Search.summary(block, locale: locale) }
        t.preview ->(block, locale:) { Search.preview(block, locale: locale) }
        t.capability :search
        t.component Blocks::SearchComponent
        # `label` the field's label (the editor's, else the CMS's word);
        # `query` the text the field holds; `state` the outcome (the
        # answer's, and `:past_end` for a page past the last); `results`
        # the page's results (`Blocks::SearchComponent::Result`); `total`
        # how many there are in all; `pagination` the `Pagination`; `action`
        # the shown page's own address, which the form is sent to;
        # `live_note?` whether the block says its results are the live
        # site's (the preview's); `close_matches?` whether the results are
        # close matches; `correction` the verified corrected search, plain
        # text, or nil; `correction_path` the block's own address searching
        # for it; `suggest_url` the suggestions endpoint, or nil for none;
        # `string(key, **options)` one of the block's words. The markup a template should keep is in
        # docs/reference/theming.md, "The Search block".
        t.theme_methods :block, :page, :label, :query, :state, :results, :total, :pagination, :action, :live_note?,
                        :close_matches?, :correction, :correction_path, :suggest_url, :string
        # The mark around a match in a snippet: its ground and its text,
        # from the base tokens in `tokens.css`, re-valued by a strong band in
        # `sections.css` (test/integration/design_tokens_test.rb holds the
        # pair).
        t.tokens themed: %w[search-mark search-mark-ink]
        t.stylesheet "search.css"
        t.sample translations: { "en" => { label: "Search the guide" }, "de" => { label: "Search label de" }, "es" => { label: "Search label es" } },
                 shows: [ "Search the guide" ]
      end
    end
  end
end
