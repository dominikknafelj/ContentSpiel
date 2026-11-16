module Blocks
  # The Search block on the public site (`BlockTypes::Search`, search spec
  # §7.2; the SiteSearch card): a GET form to the page it stands on, and for
  # a request with a query, the outcome below it. Works with no script.
  #
  # IT NEVER READS THE REQUEST. The query and the outcome are the request's
  # `SiteSearch::Answer`, handed over by the controller as the helper
  # `search_answer` (`PublicPageRendering`), which searches the first time a
  # block asks and keeps the answer for the render: two blocks on a page
  # draw one search. The block it is handed is read for its label alone.
  #
  # EVERYTHING IT PRINTS IS TEXT. A result's title and place, the query in
  # the field, in the count and in a message, are printed through ERB's own
  # escaping; the snippet is escaped by `Result#snippet` before its marks are
  # wrapped in `<mark>`, the one markup that is the component's own; and a
  # sentence that quotes the query is built by `string` from the escaped
  # words and the quote's element (`<q>`, made by `tag.q`). Nothing here, in
  # `Result` or in the template marks a string as safe
  # (`test/components/blocks/search_component_test.rb`).
  class SearchComponent < ApplicationComponent
    include Blocks::FixedWords
    include Blocks::Contract

    contract(
      accessibility: "A form with role=search, a real label for its type=search field, and a button; with the script the field is an ARIA 1.2 combobox with a named listbox, walked with the arrow keys with the caret in the field, its count said by a polite live region; the count, the close-matches line and every message are role=status; the pager is a named nav whose current page is aria-current=page and whose number links are named \"Page n\"; a match is marked and also in the words, and a matched tag is marked and followed by words a screen reader hears.",
      motion: :none,
      content_edges: %i[long short missing],
      widths: :from_container,
      interface: %i[block page label query state results total pagination action live_note? close_matches? correction correction_path suggest_url string],
      words: %w[public.blocks.search.label public.blocks.search.button public.blocks.search.results public.blocks.search.page
                public.blocks.search.pages public.blocks.search.previous public.blocks.search.next public.blocks.search.none
                public.blocks.search.past_end public.blocks.search.first_page public.blocks.search.too_long
                public.blocks.search.limited public.blocks.search.unavailable public.blocks.search.live_note
                public.blocks.search.close_matches public.blocks.search.did_you_mean public.blocks.search.tagged
                public.blocks.search.matched_tag public.blocks.search.tags_separator public.blocks.search.matched_tag_before
                public.blocks.search.matched_tag_after public.blocks.search.suggestions_unavailable
                public.blocks.search.suggestions_loading public.blocks.search.suggestions_label],
      limits: [
        "It finds what a visitor sees now: no draft, no unpublished change, no other language.",
        "No filter, and no sort; suggestions as one types with a script, none without; ten results to a page.",
        "A results page is stored by no cache."
      ]
    )

    # The block's words, the keys of `public.blocks.search`
    # (`config/locales/public.en.yml`): what `string` answers, and nothing
    # else.
    # `close_matches` and `did_you_mean` are the results' (`query:`, and
    # `correction:` the corrected search as its link); `tagged`,
    # `tags_separator` and `matched_tag` a post result's tags line
    # (`matched_tag` the words a screen reader hears after a matched tag,
    # between `matched_tag_before` and `matched_tag_after`); and the rest the
    # suggestions' as one types: the endpoint's sentences, the listbox's
    # name, the loading word and each suggestion's kind.
    STRINGS = %i[label button results page pages previous next none past_end first_page too_long limited unavailable live_note
                 close_matches did_you_mean tagged tags_separator matched_tag matched_tag_before matched_tag_after
                 suggestions no_suggestions suggestions_limited suggestions_unavailable suggestions_loading suggestions_label
                 kind_page kind_post kind_tag].freeze

    # The words that are a plural, which I18n answers as a Hash of its forms
    # when no `count:` is given.
    COUNTED = %i[results suggestions].freeze

    # How long a query word must be to match a tag word it begins
    # (`matched_tag?`); a shorter one matches only a tag word it equals.
    TAG_PREFIX_MIN = 3

    # A word of a tag or of a search, for `matched_tag?`: a run of letters,
    # marks and digits, so "kamal-proxy" is two words.
    WORD = /[\p{L}\p{M}\p{N}]+/

    # Whether the tag `name` matches the search `words` (search spec §5.3):
    # a word of the tag, in lower case, begins with one of the words of 3 or
    # more characters, or equals a shorter one. So "deploy" marks
    # "deployments", and stemming beyond a prefix is not mirrored: "ran" does
    # not mark "running". ContentSpiel's own rule, never the engine's, the
    # same for every backend.
    def self.matched_tag?(name, words)
      words = words.map(&:downcase)
      name.to_s.downcase.scan(WORD).any? do |part|
        words.any? { |word| word.length >= TAG_PREFIX_MIN ? part.start_with?(word) : part == word }
      end
    end

    # What stands in a sentence for a value handed in as markup, while I18n
    # interpolates: two NULs around its index. No locale's words hold a NUL.
    HOLE = /\u0000(\d+)\u0000/

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    private

    attr_reader :block, :page

    def answer = @answer ||= helpers.search_answer

    # The settings in the visitor's language, with the site's fallback for
    # the translated label.
    def settings = @settings ||= block.settings_object(fallback: true)

    # The editor's label, else the CMS's word.
    def label = settings&.label.presence || string(:label)

    # The text the field holds: the normalised query, or what was typed when
    # it is too long to search; nil for none.
    def query = answer.query

    # The answer's state (`SiteSearch::Answer::STATES`), and `:past_end`
    # where it found results but none on the page asked for.
    def state = answer.past_end? ? :past_end : answer.state

    def results = @results ||= answer.results.map { |item| Result.new(item, words: match_words) }

    def total = answer.total

    def pagination = answer.pagination

    # The shown page's own address, the preview's under the preview: the
    # form is sent there, and the pager's links go there with `q` and `page`.
    def action = page_url_path(page)

    def live_note? = answer.live_note?

    # Whether the results are close matches: page 1, and no exact hit found
    # (`SiteSearch::Answer#close_matches?`).
    def close_matches? = answer.close_matches?

    # The verified corrected search, plain text, or nil
    # (`SiteSearch::Answer#correction`).
    def correction = answer.correction

    # The block's own address searching for the correction, or nil: its
    # query encoded as the pager's (`URI.encode_www_form`), the one encoder
    # of every `?q=` link the block writes.
    def correction_path = correction && "#{action}?#{URI.encode_www_form(q: correction)}"

    # The suggestions endpoint the script posts to, or nil, which offers no
    # suggestions: in the preview (where `live_note?` is true) and on a site
    # with no search page. One rule with a theme's header box
    # (`ThemeHelper#search_suggest_url`).
    def suggest_url = helpers.search_suggest_url

    # The words a tag is matched by: the query's, and on close matches the
    # correction's too, in lower case.
    def match_words
      @match_words ||= [ query, (correction if close_matches?) ].compact.flat_map { |text| text.downcase.scan(WORD) }.uniq
    end

    # One of the words of `STRINGS` in the visitor's language, English where
    # that language has none; `options` are I18n's (`count:`, and the
    # values a sentence holds: `query:`, `page:`, `results:`). `too_long`'s
    # `max:` is the query's limit unless one is handed in.
    #
    # A value handed in as markup (an `ActiveSupport::SafeBuffer`: the
    # query in its `<q>`, a sentence this method made) is placed into the
    # escaped words as it is, and the answer is then markup too; any other
    # value is part of the words and escaped with them where they are
    # printed. So a quoted query is the escaped query in the CMS's element
    # and never a string marked safe.
    #
    # ONLY THOSE WORDS (`Blocks::FixedWords`): another key raises where a
    # theme is written and is empty in production, and `results` without
    # `count:` too.
    def string(key, **options)
      if COUNTED.include?(key.to_s.to_sym) && !options.key?(:count)
        return refused_word(key, "Blocks::SearchComponent#string(#{key.to_s.to_sym.inspect}) is a plural and needs count: (string(#{key.to_s.to_sym.inspect}, count: 2, query: …))")
      end

      options = { max: SiteSearch::Query::MAX_LENGTH }.merge(options) if key.to_s == "too_long"
      marked = options.select { |_, value| value.is_a?(ActiveSupport::SafeBuffer) }
      return fixed_word(key, scope: "public.blocks.search", owner: "the Search block's", **options) if marked.empty?

      holes = marked.keys.each_with_index.to_h { |name, index| [ name, "\u0000#{index}\u0000" ] }
      words = fixed_word(key, scope: "public.blocks.search", owner: "the Search block's", **options.merge(holes))
      values = marked.values
      safe_join(words.split(HOLE).each_with_index.map { |part, index| index.odd? ? values.fetch(part.to_i) : part })
    end
  end
end
