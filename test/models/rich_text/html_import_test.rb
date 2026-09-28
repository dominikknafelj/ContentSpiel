require "test_helper"

# `RichText::Document.from_html` (design spec §5): the one-off HTML → JSON
# mapper `rich_text:migrate_from_action_text` runs over every stored
# ActionText body. Unit-tested on HTML strings shaped like real Trix/ActionText
# output rather than on `ActionText::RichText` rows -- ActionText (and its
# table) is gone once this task's migration runs, so the importer can't
# depend on either, and neither can its tests (see
# `test/tasks/rich_text_migration_test.rb` for the task itself).
class RichText::HtmlImportTest < ActiveSupport::TestCase
  VIDEO_ID = "dQw4w9WgXcQ".freeze

  # A `YoutubeEmbed` attachable's sgid exactly as ActionText stored it
  # (`to_sgid(expires_in: nil, for: "attachable")`) -- built from a bare GID
  # because the `YoutubeEmbed` model no longer exists; `youtube_embeds` rows
  # are read with SQL, which `youtube_video_id:` stands in for here.
  def youtube_sgid(id = 7)
    SignedGlobalID.new(URI::GID.build(app: GlobalID.app, model_name: "YoutubeEmbed", model_id: id.to_s), for: "attachable").to_s
  end

  def import(html, **options)
    RichText::Document.from_html(html, record: nil, youtube_video_id: ->(id) { { "7" => VIDEO_ID }[id.to_s] }, **options)
  end

  def upload_blob(filename = "tiny.png", content_type: "image/png")
    ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture(filename)), filename: filename, content_type: content_type)
  end

  def text(value, *marks)
    node = { "type" => "text", "text" => value }
    node["marks"] = marks.map { |mark| mark.is_a?(Hash) ? mark : { "type" => mark.to_s } } if marks.any?
    node
  end

  def paragraph(*content) = { "type" => "paragraph", "content" => content }

  test "paragraphs and inline marks, with HTML whitespace collapsed" do
    document, unmapped = import(<<~HTML)
      <p>ContentSpiel's public site is a <strong>Page</strong> tree,
      not a <em>fixed</em> set of <del>routes</del> <b>and</b> <i>more</i> <s>x</s> <code>y</code>.</p>
    HTML

    assert_empty unmapped
    assert_empty document.validate
    assert_equal [ paragraph(
      text("ContentSpiel's public site is a "), text("Page", :bold), text(" tree, not a "), text("fixed", :italic),
      text(" set of "), text("routes", :strike), text(" "), text("and", :bold), text(" "), text("more", :italic),
      text(" "), text("x", :strike), text(" "), text("y", :code), text(".")
    ) ], document.to_h["content"]
  end

  test "nested marks come out in schema order" do
    document, = import("<p><em><strong>both</strong></em></p>")

    assert_equal [ paragraph(text("both", :bold, :italic)) ], document.to_h["content"]
  end

  # Trix writes `<div>` blocks, not `<p>`, with `<br>` for a soft break and
  # `<br><br>` where an editor pressed return twice.
  test "Trix div blocks become paragraphs, split on double line breaks" do
    document, unmapped = import("<div>One<br>still one<br><br>Two</div><div>Three</div>")

    assert_empty unmapped
    assert_equal [
      paragraph(text("One"), { "type" => "hardBreak" }, text("still one")),
      paragraph(text("Two")),
      paragraph(text("Three"))
    ], document.to_h["content"]
  end

  test "h1 becomes h2, h5 and h6 become h4, h2-h4 stay" do
    document, = import("<h1>A</h1><h2>B</h2><h3>C</h3><h4>D</h4><h5>E</h5><h6>F</h6>")

    assert_equal [ 2, 2, 3, 4, 4, 4 ], document.to_h["content"].map { |node| node.dig("attrs", "level") }
    assert_equal %w[A B C D E F], document.to_h["content"].map { |node| node.dig("content", 0, "text") }
    assert_empty document.validate
  end

  test "nested lists, blockquote, pre and hr" do
    document, unmapped = import(<<~HTML)
      <ul><li>One<ul><li>One.a</li></ul></li><li><strong>Two</strong></li></ul>
      <ol><li>First</li><li>Second</li></ol>
      <blockquote>Quoted <em>text</em></blockquote>
      <pre>def x
        1
      end</pre>
      <hr>
    HTML

    assert_empty unmapped
    assert_empty document.validate
    bullet, ordered, quote, code, rule = document.to_h["content"]

    assert_equal "bulletList", bullet["type"]
    first_item = bullet["content"][0]
    assert_equal [ paragraph(text("One")), { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ paragraph(text("One.a")) ] } ] } ], first_item["content"]
    assert_equal [ paragraph(text("Two", :bold)) ], bullet["content"][1]["content"]

    assert_equal({ "type" => "orderedList", "attrs" => { "start" => 1 }, "content" => [
      { "type" => "listItem", "content" => [ paragraph(text("First")) ] },
      { "type" => "listItem", "content" => [ paragraph(text("Second")) ] }
    ] }, ordered)

    assert_equal({ "type" => "blockquote", "content" => [ paragraph(text("Quoted "), text("text", :italic)) ] }, quote)
    assert_equal({ "type" => "codeBlock", "content" => [ text("def x\n  1\nend") ] }, code)
    assert_equal({ "type" => "horizontalRule" }, rule)
  end

  test "a YouTube embed attachment becomes a youtube node" do
    html = %(<p>Here's a talk:</p>\n<action-text-attachment sgid="#{youtube_sgid}" content-type="application/octet-stream"></action-text-attachment>)
    document, unmapped = import(html)

    assert_empty unmapped
    assert_empty document.validate
    assert_equal [ paragraph(text("Here's a talk:")), { "type" => "youtube", "attrs" => { "id" => VIDEO_ID } } ], document.to_h["content"]
  end

  # Trix places an attachment inline, inside the block it was dropped into
  # -- the paragraph splits around the (block-level) embed.
  test "an attachment inside a Trix div splits the paragraph around it" do
    document, = import(%(<div>Before<action-text-attachment sgid="#{youtube_sgid}"></action-text-attachment>After</div>))

    assert_equal %w[paragraph youtube paragraph], document.to_h["content"].map { |node| node["type"] }
  end

  # The paste handler's offline fallback stored the embed markup itself as
  # a content attachment (`content-type="text/html"`, `content="..."`)
  # instead of a `YoutubeEmbed` sgid.
  test "a content attachment carrying a youtube-nocookie iframe becomes a youtube node" do
    content = ERB::Util.html_escape(%(<div class="youtube-embed__frame"><iframe src="https://www.youtube-nocookie.com/embed/#{VIDEO_ID}"></iframe></div>))
    document, unmapped = import(%(<action-text-attachment content-type="text/html" content="#{content}"></action-text-attachment>))

    assert_empty unmapped
    assert_equal [ { "type" => "youtube", "attrs" => { "id" => VIDEO_ID } } ], document.to_h["content"]
  end

  test "a YouTube sgid whose row is gone is reported, not guessed" do
    document, unmapped = import(%(<p>Talk</p><action-text-attachment sgid="#{youtube_sgid(99)}"></action-text-attachment>))

    assert_equal [ paragraph(text("Talk")) ], document.to_h["content"]
    assert_equal 1, unmapped.size
    assert_includes unmapped.first, "YoutubeEmbed"
  end

  test "an image blob attachment becomes a MediaAsset re-attaching the same blob, plus an image node" do
    blob = upload_blob
    html = %(<div><action-text-attachment sgid="#{blob.to_sgid(for: "attachable")}" content-type="image/png" url="http://localhost:3000/rails/active_storage/blobs/redirect/x/tiny.png" filename="tiny.png" filesize="#{blob.byte_size}" width="1" height="1" presentation="gallery" caption="A tiny dot"></action-text-attachment></div>)

    document, unmapped = assert_difference(-> { MediaAsset.count }, 1) { import(html) }

    assert_empty unmapped
    assert_empty document.validate
    asset = MediaAsset.last
    assert_equal blob, asset.file.blob
    assert_equal [ { "type" => "image", "attrs" => { "asset_id" => asset.id, "caption" => "A tiny dot" } } ], document.to_h["content"]
  end

  test "the same blob in a second body (or locale) reuses its MediaAsset" do
    blob = upload_blob
    html = %(<action-text-attachment sgid="#{blob.to_sgid(for: "attachable")}" content-type="image/png"></action-text-attachment>)

    first, = import(html)
    second, = assert_no_difference(-> { MediaAsset.count }) { import(html) }

    assert_equal first.to_h, second.to_h
  end

  test "a blob that isn't an allowed image is reported and gets no MediaAsset, its caption kept" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 not an image"), filename: "notes.pdf", content_type: "application/pdf")
    html = %(<action-text-attachment sgid="#{blob.to_sgid(for: "attachable")}" content-type="application/pdf" filename="notes.pdf" caption="My notes"></action-text-attachment>)

    document, unmapped = assert_no_difference(-> { MediaAsset.count }) { import(html) }

    assert_equal [ paragraph(text("My notes")) ], document.to_h["content"]
    assert_equal 1, unmapped.size
    assert_includes unmapped.first, "notes.pdf"
  end

  test "a forged sgid is reported and not resolved" do
    document, unmapped = import(%(<p>Hi</p><action-text-attachment sgid="forged--abc" content-type="image/png"></action-text-attachment>))

    assert_equal [ paragraph(text("Hi")) ], document.to_h["content"]
    assert_equal 1, unmapped.size
  end

  test "a link to this site's public URL, absolute or relative, becomes an internalLink" do
    about = create_page(title: "About")
    absolute = PublicSite::Urls.new.url_for(about, "en")

    document, unmapped = import(%(<p><a href="#{absolute}">About us</a> and <a href="/about/">again</a></p>))

    assert_empty unmapped
    assert_empty document.validate
    internal = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => about.id } }
    assert_equal [ paragraph(text("About us", internal), text(" and "), text("again", internal)) ], document.to_h["content"]
  end

  test "a locale-prefixed internal URL resolves in that locale" do
    about = create_page(title: "About", translations: { "de" => { title: "Ueber uns", slug: "ueber-uns" } })

    document, = import(%(<p><a href="/de/ueber-uns">Ueber uns</a></p>))

    assert_equal({ "type" => "internalLink", "attrs" => { "type" => "page", "id" => about.id } }, document.to_h.dig("content", 0, "content", 0, "marks", 0))
  end

  test "an external link, an unresolved relative link and a mailto stay links" do
    document, unmapped = import(%(<p><a href="https://rubyonrails.org/">Rails</a> <a href="/nowhere">x</a> <a href="mailto:me@example.com">mail</a></p>))

    assert_empty unmapped
    hrefs = document.to_h.dig("content", 0, "content").filter_map { |node| node.dig("marks", 0, "attrs", "href") }
    assert_equal [ "https://rubyonrails.org/", "/nowhere", "mailto:me@example.com" ], hrefs
    assert_empty document.validate
  end

  test "unknown tags keep their text and are reported" do
    document, unmapped = import("<p>Keep <u>this</u> <span>too</span></p><table><tr><td>cell</td></tr></table>")

    assert_empty document.validate
    assert_equal "Keep this too", document.to_h.dig("content", 0, "content").sum("") { |node| node["text"] }
    assert_equal "cell", document.to_h.dig("content", 1, "content", 0, "text")
    assert unmapped.any? { |fragment| fragment.include?("<u>") }
    assert unmapped.any? { |fragment| fragment.include?("<table>") }
  end

  test "migrated hostile HTML stays inert" do
    html = <<~HTML
      <p>Hi<script>alert(1)</script></p>
      <iframe src="https://evil.example/x"></iframe>
      <p><a href="javascript:alert(2)">click</a> <a href="java&#x09;script:alert(3)">tab</a></p>
      <p onclick="alert(4)"><img src="x" onerror="alert(5)">text</p>
      <style>body { display: none }</style>
    HTML

    document, unmapped = import(html)

    assert_empty document.validate
    json = document.to_h.to_json
    %w[script alert iframe evil.example javascript onerror onclick display].each { |needle| assert_not_includes json, needle }
    assert_includes json, "click"

    rendered = document.to_html(locale: "en")
    %w[<script alert( <iframe evil.example javascript: onerror onclick].each { |needle| assert_not_includes rendered, needle }
    assert_includes rendered, "click"

    assert unmapped.any? { |fragment| fragment.include?("<script>") }
    assert unmapped.any? { |fragment| fragment.include?("<iframe>") }
    assert unmapped.any? { |fragment| fragment.include?("javascript:alert(2)") }
  end

  test "blank HTML imports as an empty document" do
    [ nil, "", "  \n", "<div><br></div>" ].each do |html|
      document, unmapped = import(html)

      assert document.blank?, html.inspect
      assert_empty unmapped
    end
  end

  test "absurdly deep nesting still yields a valid document" do
    html = ("<blockquote>" * 120) + "deep" + ("</blockquote>" * 120)

    document, = import(html)

    assert_empty document.validate
    assert_includes document.to_h.to_json, "deep"
  end

  # Final fix wave (A): imported HTML goes through `RichText::ContentRepair`
  # too, so a migrated body is one the editor can load -- a code face
  # inside bold, an empty quote, a list item opening with an embed.
  test "imported documents satisfy the editor's content model" do
    html = %(<p><strong><code>x</code></strong> and <a href="https://example.com"><code>y</code></a></p><blockquote></blockquote>) +
      %(<ul><li><action-text-attachment sgid="#{youtube_sgid}" content-type="application/octet-stream"></action-text-attachment></li></ul>)
    document, unmapped = RichText::HtmlImport.new(youtube_video_id: ->(_id) { VIDEO_ID }).call(html)

    assert_empty document.validate
    texts = document.to_h.dig("content", 0, "content")
    assert_equal [ { "type" => "code" } ], texts.first["marks"]
    assert_equal [ "link" ], texts.last["marks"].map { |mark| mark["type"] }
    assert_equal "paragraph", document.to_h.dig("content", 1, "content", 0, "content", 0, "type")
    assert unmapped.any? { |message| message.include?("code") }
  end
end
