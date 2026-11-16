require "test_helper"

# What the public site's scripts may not do (search 2 spec §11). The
# suggestions' script draws what another request answered, a title or a tag
# a visitor never typed, into the page: it builds its nodes with
# `textContent` and `document.createElement`, and never hands a text to the
# HTML parser, so nothing it is answered can become markup.
class PublicScriptGuardsTest < ActiveSupport::TestCase
  SEARCH_SUGGEST = Rails.root.join("app/javascript/controllers/search_suggest_controller.js")

  test "search_suggest writes no HTML from text" do
    source = SEARCH_SUGGEST.read
    %w[innerHTML outerHTML insertAdjacentHTML DOMParser document.write createContextualFragment srcdoc].each do |name|
      refute_includes source, name, "#{SEARCH_SUGGEST.basename} names #{name}"
    end
  end
end
