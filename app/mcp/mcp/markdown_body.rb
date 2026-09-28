# Shared by the Post MCP tools that write a body (`create_post`,
# `update_post`): `body` is Markdown in and out (tiptap spec §3.4), so a
# client never sees or sends the Tiptap JSON the post actually stores. The
# conversion runs *here*, in the tool, not in `Posts::Save`: the service
# takes the document Hash every other caller (admin, seeds, starter content)
# hands it, and Markdown is only MCP's wire format.
#
# `RichText::Document.from_markdown` never fails the write -- what it can't
# represent (an unknown directive, raw HTML, a `cs:` link to a record that
# doesn't exist) degrades to text or is dropped, and comes back as a
# warning. Those warnings are the client's only signal that its body didn't
# land exactly as sent, so `post_response` appends them as a second text
# item after the post's own JSON: the first item stays parseable JSON (what
# every client already reads), and a model reading the response text still
# sees the warnings. No compatibility shim for the old HTML `body` -- there
# are no MCP clients yet (global constraints).
#
# `extend`ed, like `Mcp::ErrorResponse`, because every tool's `.call` is a
# class method; see that module's own comment for why this lives under
# app/mcp/mcp/.
module Mcp
  module MarkdownBody
    DESCRIPTION = "Markdown (CommonMark). Headings are ## to ####; bold, italic, ~~strike~~, `code`, links, " \
      "bullet/ordered lists, > quotes, fenced code blocks and --- rules are supported. Embeds are " \
      "directives on a line of their own: ::youtube{id=\"VIDEO_ID\"} (the 11-character YouTube id) and " \
      "::image{asset=\"42\" alt=\"…\" caption=\"…\"} (an uploaded media asset's id). Link to another " \
      "page or post of this site with [text](cs:page/<id>) or [text](cs:post/<id>) -- those links " \
      "follow renames. Raw HTML and unknown directives are not stored; they are dropped or kept as " \
      "plain text and reported as warnings in the response.".freeze

    # `[document_hash, warnings]` for `translations[locale][:body]`.
    def markdown_body(markdown)
      document, warnings = RichText::Document.from_markdown(markdown)
      [ document.to_h, warnings ]
    end

    def post_response(data, warnings = [])
      content = [ { type: "text", text: data.to_json } ]
      if warnings.any?
        content << { type: "text", text: "Markdown conversion warnings for body:\n#{warnings.map { |warning| "- #{warning}" }.join("\n")}" }
      end

      MCP::Tool::Response.new(content, structured_content: data)
    end
  end
end
