require "test_helper"

# The built-in backend (spec §6) holds the contract every backend holds, on
# documents of real copies: its query reads the site's own tables (the copy
# in force by its entries' `live_at`, the record's publication, its
# address), so a contract document is a page published through the
# services, and its view is the clock's: scheduled at `shown_from`, with a
# change scheduled at `shown_until`.
class SiteSearch::PostgresTest < ActiveSupport::TestCase
  include SiteSearchBackendContract

  def backend = @backend ||= SiteSearch::Postgres.new

  # A page with these words in `language`, an address of its own in every
  # language, published a minute before `contract_now` or scheduled
  # at `shown_from`. With `shown_until`, a change of other words is
  # scheduled then and indexed, as taking it does, so the copy in force
  # gives way to it by the clock.
  def contract_document(title:, body: "", code: "", language: "en", shown_from: nil, shown_until: nil)
    @contract_pages = (@contract_pages || 0) + 1
    slug = "contract-#{@contract_pages}"
    translations = Locales.enabled.index_with { { slug: slug } }.merge(language => { title: title, slug: slug })
    page, copy = travel_to(contract_now - 1.minute) do
      page = create_page(title: "Contract #{@contract_pages}", published: false, translations: translations)
      rich_text = save_block(page, { block_type: "rich_text" }, language => { body: rich_doc(body) }) if body.present?
      coded = save_block(page, { block_type: "code", settings: { "code" => code } }) if code.present?
      assert Pages::Save.call(page.reload, attributes: { published_at: shown_from || Time.current }).ok?
      copy = Publishing.current(page) || Publishing.pending(page)

      if shown_until
        assert Pages::Save.call(page.reload, translations: { language => { title: "Superseded #{@contract_pages}" } }).ok?
        save_block(rich_text, {}, language => { body: rich_doc("Superseded") }) if rich_text
        save_block(coded, { settings: { "code" => "superseded" } }) if coded
        publish_changes(page, at: shown_until)
        backend.index(SiteSearch::Documents.for(Publishing.pending(page, now: Time.current), now: Time.current))
      end
      [ page, copy ]
    end
    assert_equal page.id, copy.record_id
    # Taking a copy indexes it in every language (`SiteSearch::Indexing`):
    # the contract indexes its document itself, so only a scheduled change's
    # entry in the document's language is kept.
    backend.remove(record_type: "Page", record_id: page.id, languages: Locales.enabled - [ language ])
    backend.remove(record_type: "Page", record_id: page.id, copy_ids: [ copy.id ])

    SiteSearch::Documents.for(copy, now: contract_now).find { |document| document.language == language }
  end

  def save_block(block_or_page, attributes, translations = {})
    block = block_or_page.is_a?(ContentBlock) ? block_or_page : ContentBlock.new(owner: block_or_page)
    result = ContentBlocks::Save.call(block, attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def entry_of(copy, locale) = SiteSearch::Entry.find_by!(published_version_id: copy.id, locale: locale)

  test "an entry is built with its locale's configuration, the fallback text included" do
    page = publish_changes(create_page(title: "Running"))
    copy = Publishing.current(page)
    backend.clear

    backend.index(SiteSearch::Documents.for(copy, now: Time.current))

    english = entry_of(copy, "en")
    spanish = entry_of(copy, "es")
    assert_equal [ "english", "spanish" ], [ english.config, spanish.config ]
    assert_equal "'run':1A", english.document, "English stems the title"
    assert_equal "'running':1A", spanish.document, "the Spanish entry holds the English title, parsed as Spanish"
    assert_equal 1, backend.entry_count
  end

  test "a withdrawn pending copy takes its entries with it" do
    page = publish_changes(create_page(title: "Harbour"))
    assert Pages::Save.call(page, translations: { "en" => { title: "Harbour at dawn" } }).ok?
    publish_changes(page, at: 1.day.from_now)
    pending = Publishing.pending(page)
    backend.index(SiteSearch::Documents.for_record(page.reload, now: Time.current))
    assert_equal 3, SiteSearch::Entry.where(published_version_id: pending.id).count

    assert Publishing::CancelScheduledChange.call(page.reload).ok?

    assert_not SiteSearch::Entry.exists?(published_version_id: pending.id)
    assert SiteSearch::Entry.exists?(published_version_id: Publishing.current(page).id)
  end

  test "health is ok and the backend writes in the caller's transaction" do
    assert_equal SiteSearch::Health.new(status: :ok, detail: nil), backend.health(deadline: contract_deadline)
    assert SiteSearch::Backends.inline?(SiteSearch::Backends::BUILT_IN), "its registration says so"
  end

  test "entry_count counts the records with an entry, not the entries" do
    page = publish_changes(create_page(title: "Harbour"))
    post = publish_changes(create_post(title: "Tides"))
    backend.clear
    backend.index(SiteSearch::Documents.for(Publishing.current(page), now: Time.current))
    backend.index(SiteSearch::Documents.for(Publishing.current(post), now: Time.current))

    assert_equal 6, SiteSearch::Entry.count
    assert_equal 2, backend.entry_count
  end
end
