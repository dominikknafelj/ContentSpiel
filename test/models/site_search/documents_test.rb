require "test_helper"

# A published copy turned into words (spec §4.1, §4.2): one plain document
# per enabled language, its fields at their weights, read through the
# language's fallback chain, from the copy and never the rows.
class SiteSearch::DocumentsTest < ActiveSupport::TestCase
  def field(doc, name) = doc.fields.find { |each| each.name == name }

  def page_with_blocks(title: "Harbour guide", translations: {})
    page = create_page(title: title, translations: translations)
    assert Pages::Save.call(page, translations: { "en" => { subtitle: "Boats and tides", meta_description: "Where to moor" } }).ok?
    save_block(page, { block_type: "rich_text" }, "en" => { body: rich_doc("Tides turn twice a day.") })
    save_block(page, { block_type: "code", settings: { "code" => "tide --today" } })
    publish_changes(page)
  end

  def save_block(page, attributes, translations = {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "a page's copy gives one document per enabled language, keyed Page:id:copy:locale" do
    page = page_with_blocks
    version = Publishing.current(page)

    docs = SiteSearch::Documents.for(version, now: Time.current)

    assert_equal [ "Page:#{page.id}:#{version.id}:de", "Page:#{page.id}:#{version.id}:en", "Page:#{page.id}:#{version.id}:es" ], docs.map(&:key).sort
    doc = docs.find { |each| each.language == "en" }
    assert_equal [ "Page", page.id, version.id ], [ doc.record_type, doc.record_id, doc.copy_id ]
    assert_equal version.live_at, doc.live_at
    assert_equal PublicSite::Urls.new.path_for(page, "en"), doc.url
    assert_equal "/de#{PublicSite::Paths.current_path(page, "de")}", docs.find { |each| each.language == "de" }.url
  end

  def document_of(record, locale) = SiteSearch::Documents.for(Publishing.current(record), now: Time.current).find { |each| each.language == locale }

  test "the title is A, the summary B, the blocks C, code D" do
    doc = document_of(page_with_blocks, "en")

    assert_equal [ [ "title", :a ], [ "summary", :b ], [ "body", :c ], [ "code", :d ] ], doc.fields.map { [ _1.name, _1.weight ] }
    assert_equal "Harbour guide", field(doc, "title").text
    assert_equal "Boats and tides Where to moor harbour guide", field(doc, "summary").text
    assert_equal "Tides turn twice a day.", field(doc, "body").text
    assert_equal "tide --today", field(doc, "code").text
    assert_equal "Tides turn twice a day.", doc.text
  end

  test "tags are A, meta title and slug B" do
    page = create_page(title: "Guide", translations: { "en" => { title: "Guide", subtitle: "Sub", meta_title: "Meta words", slug: "zero-downtime-deploys" } })
    summary = field(document_of(page, "en"), "summary")
    assert_equal :b, summary.weight
    assert_includes summary.text, "Meta words"
    assert_includes summary.text, "zero downtime deploys"
    assert_not_includes summary.text, "zero-downtime"

    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    created = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: [ "deployment" ] },
      translations: { "en" => { title: "P", excerpt: "Ex", slug: "my-post" } })
    assert created.ok?, created.errors.to_sentence
    post_doc = document_of(created.record, "en")
    assert_equal [ :a, "deployment" ], [ field(post_doc, "tags").weight, field(post_doc, "tags").text ]
    assert_equal "Ex my post", field(post_doc, "summary").text
  end

  # A page's slug is read in the document's language: the Spanish document
  # holds the Spanish slug, with no language prefix.
  test "the slug is the address's last segment in the document's language" do
    page = create_page(title: "Harbour", translations: { "es" => { title: "Puerto", slug: "puerto-viejo" } })
    assert_equal "harbour", field(document_of(page, "en"), "summary").text
    assert_equal "puerto viejo", field(document_of(page, "es"), "summary").text
  end

  test "the homepage's slug adds nothing to its summary" do
    home = root_page
    assert_equal [ "" ], Locales.enabled.map { |code| field(document_of(home, code), "summary").text }.uniq
  end

  # A post has no meta description of its own (`Post` translates title,
  # slug and excerpt): its summary is its excerpt.
  test "a post gives its excerpt and slug at B, its copy's tag names at A and its translated_metadata strings at C" do
    saved = ContentTypes.all.dup
    ContentTypes.register("test/report") do |t|
      t.label "Report"
      t.list_component Posts::BlogListComponent
      t.detail_component Posts::DetailComponent
      t.field :standfirst, :text, translated: true
      t.field :venue, :string
    end
    post = create_post(title: "Spring report", content_type: "test/report", tags: %w[Weather Tides])
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "A short look back", body: rich_doc("The rain was heavy.") } },
                                  attributes: { fields: { "standfirst" => "Rain came early", "venue" => "Untranslated hall" } }).ok?
    publish_changes(post)

    doc = SiteSearch::Documents.for(Publishing.current(post), now: Time.current).find { |each| each.language == "en" }

    assert_equal [ [ "title", :a ], [ "summary", :b ], [ "tags", :a ], [ "body", :c ], [ "code", :d ] ], doc.fields.map { [ _1.name, _1.weight ] }
    assert_equal "A short look back", field(doc, "summary").text, "a post no list shows has no address, so no slug words"
    assert_equal "tides weather", field(doc, "tags").text.split.sort.join(" ")
    assert_equal "The rain was heavy. Rain came early", field(doc, "body").text
    assert_not_includes doc.fields.map(&:text).join(" "), "Untranslated hall"
  ensure
    ContentTypes.reset!
    saved.each { |definition| ContentTypes.registry_put(definition) }
  end

  test "a Spanish document reads each field through the fallback chain" do
    page = create_page(title: "Only in English")
    assert Pages::Save.call(page, translations: { "de" => { title: "Nur auf Deutsch" } }).ok?
    publish_changes(page)

    docs = SiteSearch::Documents.for(Publishing.current(page), now: Time.current)

    assert_equal "Only in English", field(docs.find { |doc| doc.language == "es" }, "title").text
    assert_equal "Nur auf Deutsch", field(docs.find { |doc| doc.language == "de" }, "title").text
  end

  test "a scheduled change's document is shown from its live_at, and the copy in force's until it" do
    page = create_page(title: "Before")
    assert Pages::Save.call(page, translations: { "en" => { title: "After" } }).ok?
    live_at = 2.days.from_now.change(usec: 0)
    publish_changes(page, at: live_at)
    current = Publishing.current(page)
    now = Time.current

    docs = SiteSearch::Documents.for_record(page.reload, now: now)

    current_doc = docs.find { |doc| doc.copy_id == current.id && doc.language == "en" }
    pending_doc = docs.find { |doc| doc.copy_id == Publishing.pending(page).id && doc.language == "en" }
    assert_equal 6, docs.size
    assert_equal "Before", field(current_doc, "title").text
    assert_equal "After", field(pending_doc, "title").text
    assert_equal live_at, pending_doc.shown_from
    assert_nil pending_doc.shown_until
    assert_equal live_at, current_doc.shown_until
    assert_equal [ current.live_at, page.published_at ].max, current_doc.shown_from
  end

  test "words typed into the rows and not published are in no document" do
    page = page_with_blocks
    assert Pages::Save.call(page, translations: { "en" => { title: "Unpublished title" } }).ok?
    save_block(page, { block_type: "rich_text" }, "en" => { body: rich_doc("Unpublished words") })

    docs = SiteSearch::Documents.for_record(page.reload, now: Time.current)

    text = docs.flat_map { |doc| doc.fields.map(&:text) }.join(" ")
    assert_not_includes text, "Unpublished"
    assert_includes text, "Harbour guide"
  end

  test "stored text holds no marker character" do
    page = create_page(title: "Marks \u{E000}x\u{E001} here")
    typed = "A \u{E000}x\u{E001} and <b>bold</b>\tand\u0001 more  spaces"
    save_block(page, { block_type: "rich_text" }, "en" => { body: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => typed } ] } ] } })
    publish_changes(page)

    doc = SiteSearch::Documents.for(Publishing.current(page), now: Time.current).find { |each| each.language == "en" }

    doc.fields.map(&:text).push(doc.text).each do |text|
      assert_no_match(/[\u{E000}\u{E001}<>[:cntrl:]]/, text)
      assert_no_match(/\s\s/, text)
    end
    assert_equal "Marks x here", field(doc, "title").text
    assert_equal "A x and bold and more spaces", doc.text
    assert_equal "a b", SiteSearch::Documents.plain(("a\u{E000}\u{E001} <i>b</i>\u0000".b + "\xFF".b).force_encoding("UTF-8"))
  end

  test "text is cut at MAX_TEXT at a word boundary" do
    words = Array.new(SiteSearch::MAX_TEXT / 7 + 10) { |i| "w#{i.to_s.rjust(5, "0")}" }
    long = words.join(" ")
    assert_operator long.length, :>, SiteSearch::MAX_TEXT

    page = create_page(title: "Long")
    save_block(page, { block_type: "code", settings: { "code" => "x" } })
    publish_changes(page)
    doc = SiteSearch::Documents.for(Publishing.current(page), now: Time.current).first

    cut = SiteSearch::Documents.plain(long).then { |text| SiteSearch.cut(text) }
    assert_operator cut.length, :<=, SiteSearch::MAX_TEXT
    assert_equal " ", long[cut.length], "the cut ends at a word's end"
    assert long.start_with?(cut)

    field = SiteSearch::Field.new(name: "code", weight: :d, text: long)
    assert_operator field.text.length, :<=, SiteSearch::MAX_TEXT, "every field is cut, the code field too"
    assert_equal " ", long[field.text.length]
    assert_operator doc.with(text: long).text.length, :<=, SiteSearch::MAX_TEXT
  end

  # One Code block is capped below MAX_TEXT (`CodeHighlight::MAX_CHARACTERS`);
  # a page of them is not, and its code field would overflow the tsvector.
  test "a page's Code blocks together are cut at MAX_TEXT in the code field" do
    page = create_page(title: "Big code")
    code = ([ "line" ] * (CodeHighlight::MAX_CHARACTERS / 5)).join("\n")
    (SiteSearch::MAX_TEXT / code.length + 1).times { save_block(page, { block_type: "code", settings: { "code" => code } }) }
    publish_changes(page)

    doc = SiteSearch::Documents.for(Publishing.current(page), now: Time.current).first

    assert_operator field(doc, "code").text.length, :<=, SiteSearch::MAX_TEXT
    assert_operator field(doc, "code").text.length, :>, SiteSearch::MAX_TEXT - 10
  end

  test "a trashed or unpublished record has no documents" do
    draft = create_page(title: "Draft", published: false)
    trashed = create_page(title: "Trashed")
    assert Trash::Move.call(trashed).ok?

    assert_equal [], SiteSearch::Documents.for_record(draft.reload, now: Time.current)
    assert_equal [], SiteSearch::Documents.for_record(trashed.reload, now: Time.current)
    assert_equal 3, SiteSearch::Documents.for_record(create_page(title: "Live"), now: Time.current).size
  end
end
