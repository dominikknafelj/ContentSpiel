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

    def self.register
      BlockTypes.register :search do |t|
        t.label "Search"
        t.icon "search", family: :form
        t.field :label, :string, translated: true, max: LABEL_LENGTH
        t.capability :search
        t.component Blocks::SearchComponent
        # `label` the field's label (the editor's, else the CMS's word);
        # `query` the text the field holds; `state` the outcome (the
        # answer's, and `:past_end` for a page past the last); `results`
        # the page's results (`Blocks::SearchComponent::Result`); `total`
        # how many there are in all; `pagination` the `Pagination`; `action`
        # the shown page's own address, which the form is sent to;
        # `live_note?` whether the block says its results are the live
        # site's (the preview's); `string(key, **options)` one of the
        # block's words. The markup a template should keep is in
        # docs/reference/theming.md, "The Search block".
        t.theme_methods :block, :page, :label, :query, :state, :results, :total, :pagination, :action, :live_note?, :string
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
