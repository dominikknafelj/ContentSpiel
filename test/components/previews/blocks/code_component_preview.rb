require_relative "../preview_fixtures"

module Blocks
  # `Blocks::CodeComponent` (code block spec §4): a coloured sample with its
  # file name, plain text with no head but the button, and one with a caption
  # and a line long enough to scroll.
  class CodeComponentPreview < ViewComponent::Preview
    def ruby_with_file_name
      render component({ "language" => "ruby", "filename" => "app/models/greeting.rb", "code" => "# Says hello\nclass Greeting\n  def to_s = \"Hello, \#{@name}\"\nend" })
    end

    def plain_text
      render component({ "code" => "No language: no colours, and a head that holds only the button." })
    end

    def erb_with_caption_and_a_long_line
      render component({ "language" => "erb", "filename" => "app/views/pages/show.html.erb",
        "code" => %(<h1 class="title"><%= translated(@page, :title) %></h1>\n<p>#{"A long line that scrolls. " * 12}</p>) },
        caption: "The page's heading")
    end

    private

    def component(settings, caption: "")
      page = PreviewFixtures.page(title: "Code preview")
      block = page.content_blocks.create!(block_type: :code, position: 0, settings: settings, caption: caption)

      Blocks::CodeComponent.new(block: block, page: page)
    end
  end
end
