# The Search block in a request's test: `place_search_block(page)` puts one
# on `page` (in a section's column with `section:`) and publishes it, so the
# page's copy holds it; `search_drawn` reads what the first Search block of
# the response drew, as
#
#   { state: "results" | "none" | "past_end" | "too_long" | "limited" | "unavailable" | "empty",
#     live_note: true | false,
#     results: [ [ title, url_path ], … ] }
#
# or nil when the response drew none. The state is read from the markup
# the default template writes for it (the list, or the sentence of a
# message, in English), so a test of the request reads the real block.
module SearchBlock
  BLOCK = ".content-block--search".freeze

  def place_search_block(page, section: nil)
    placement = section ? { section_id: section.id, section_column: 1 } : {}
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search", **placement })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page)
    result.record
  end

  def search_drawn(html = response.body)
    block = Nokogiri::HTML5(html).at_css(BLOCK) or return nil

    { state: drawn_search_state(block), live_note: block.at_css(".search__note").present?,
      results: block.css(".search__result a.search__title").map { |link| [ link.text, link["href"] ] } }
  end

  private

  def drawn_search_state(block)
    return "results" if block.at_css(".search__results")

    message = block.at_css(".search__message")&.text or return "empty"
    words = %i[limited unavailable].index_with { |key| I18n.t("public.blocks.search.#{key}") }
    words[:too_long] = I18n.t("public.blocks.search.too_long", max: SiteSearch::Query::MAX_LENGTH)
    found = words.find { |_, sentence| message == sentence }&.first
    return found.to_s if found
    return "past_end" if message.include?(", but there is no page ")
    return "none" if message.start_with?("Nothing found for ")

    raise ArgumentError, "a Search block's message this helper does not know: #{message.inspect}"
  end
end
