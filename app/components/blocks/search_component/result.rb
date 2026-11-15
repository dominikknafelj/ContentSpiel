module Blocks
  class SearchComponent
    # One result as a template may draw it (search spec §7.2): what a theme
    # is promised of each of `results`, over a `SiteSearch::Shown::Item`,
    # whose record a template is not handed.
    #
    #   title     the title as published, in the language shown
    #   url_path  its address in that language
    #   kind      :page or :post
    #   where     a page's place: the titles of the pages above it, the
    #             homepage first, joined by " › "; nil for a post and for the
    #             homepage
    #   date      a post's date as `post_date` writes it; nil for a page
    #   snippet   the words around the match, escaped, each match in <mark>
    #   tags      a post's tags as its copy in force holds them, in its order,
    #             each a `Result::Tag` (`name`, `matched?`); [] for a page
    #   close?    whether it was found as a close match, not an exact one
    #
    # Every one but `snippet` is plain text, which a template prints through
    # ERB's escaping: a tag's name too, and whether it matched is a flag,
    # never markup.
    class Result
      include ActionView::Helpers::TagHelper
      include ActionView::Helpers::OutputSafetyHelper

      PLACE_SEPARATOR = " › ".freeze
      # `ThemeHelper#post_date`'s format, so a result's date reads as the
      # post list's (test/components/blocks/search_component_test.rb holds
      # the two equal).
      DATE_FORMAT = "%-d %b %Y".freeze

      # One of a post's tags: `name` as the copy holds it, plain text;
      # `matched?` whether it matches the search
      # (`Blocks::SearchComponent.matched_tag?`).
      Tag = Data.define(:name, :matched) do
        def matched? = matched == true
      end

      # `words` are what a tag is matched by: the query's words, and on close
      # matches the correction's too (`Blocks::SearchComponent#match_words`).
      def initialize(item, words:)
        @item = item
        @words = words
      end

      def title = item.title

      def url_path = item.url_path

      def kind = item.kind

      def where = item.where&.join(PLACE_SEPARATOR)

      def date = item.date&.strftime(DATE_FORMAT)

      # Built with `Tag[…]`: `Tag.` reads, to the public readers' guard
      # (`test/lib/public_readers_test.rb`), as the model's rows, which this
      # value is not.
      def tags = @tags ||= item.tags.map { |name| Tag[name: name, matched: SearchComponent.matched_tag?(name, words)] }

      def close? = item.close == true

      # The backend's text with its marks (`SiteSearch::Snippet`, ranges in
      # characters and never markup): each piece is escaped by `safe_join`
      # and each marked piece wrapped by `content_tag`, so the text can add
      # no element and no attribute, and the only markup is the marks. A
      # mark that is no `[start, length]` of Integers starting inside the
      # text, or that overlaps the one before it, is left out; the words are
      # kept.
      def snippet
        text = item.snippet&.text.to_s
        parts = []
        at = 0
        marks_within(text).sort_by(&:first).each do |start, length|
          next if start < at

          parts << text[at...start] << content_tag(:mark, text[start, length])
          at = start + length
        end
        parts << text[at..].to_s
        safe_join(parts)
      end

      private

      attr_reader :item, :words

      def marks_within(text)
        Array(item.snippet&.marks).select do |mark|
          mark.is_a?(Array) && mark.size == 2 && mark.all?(Integer) && mark.first >= 0 && mark.first < text.length && mark.last.positive?
        end
      end
    end
  end
end
