# `with_search_probe { … }`: `search_probe`, a test-only block type that
# claims `:search` and draws the request's `search_answer` as plain text, so
# the request's tests (the limit, the cache headers, the privacy, the
# preview) read what a Search block is handed before the Search block
# exists. Bare-named because `:search` is refused to a type from outside;
# the registries are prepared again afterwards, as `with_test_types` does.
#
# `place_search_probe(page)` puts one on `page` and publishes it, so the
# page's copy holds it.
#
# What it prints, one line each:
#   state: <the answer's state>
#   live_note: <true|false>
#   result: <title> <url_path>
class SearchProbeComponent < ApplicationComponent
  erb_template <<~ERB
    <pre class="search-probe">state: <%= answer.state %>
    live_note: <%= answer.live_note? %>
    <% answer.results.each do |item| %>result: <%= item.title %> <%= item.url_path %>
    <% end %></pre>
  ERB

  def initialize(block:, page:)
    @block = block
    @page = page
  end

  private

  def answer = helpers.search_answer
end

module SearchProbe
  def with_search_probe
    BlockTypes.register "search_probe" do |t|
      t.label "Search probe"
      t.capability :search
      t.component SearchProbeComponent
      t.theme_methods :block, :page
      t.sample shows: [ "state:" ]
    end
    yield
  ensure
    Rails.application.reloader.prepare!
  end

  def place_search_probe(page)
    page.content_blocks.create!(block_type: "search_probe", position: page.content_blocks.count)
    publish_changes(page)
  end

  # What the probe printed, as `{ state:, live_note:, results: [[title, path], …] }`.
  def probe
    text = Nokogiri::HTML5(response.body).at_css("pre.search-probe")&.text
    return nil if text.nil?

    lines = text.lines.map(&:strip).reject(&:empty?)
    { state: lines.find { |line| line.start_with?("state: ") }&.delete_prefix("state: "),
      live_note: lines.find { |line| line.start_with?("live_note: ") }&.delete_prefix("live_note: "),
      results: lines.select { |line| line.start_with?("result: ") }.map { |line| line.delete_prefix("result: ").rpartition(" ").values_at(0, 2) } }
  end
end
