require "test_helper"

# `translation_states` is derived data like `public_paths` and
# `media_usages`: these tests pin that the save services keep it current and
# that its readers answer without recomputing.
class Translations::StateIndexTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    with_locales(%w[en de es], default: "en")
  end

  def state(record, locale) = Translations::State.find_by(record_type: record.class.polymorphic_name, record_id: record.id, locale: locale)

  # Statements actually sent to the database (same helper as the status tests).
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def create_block(page, attributes: { block_type: "rich_text" }, translations: {})
    result = ContentBlocks::Save.call(page.content_blocks.new, attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "a new page is missing in every other language" do
    page = create_page(title: "About")
    assert_equal %w[missing missing], %w[de es].map { |l| state(page, l).state }
    assert_equal 1, state(page, "de").missing_count
    assert_nil state(page, "en")
  end

  test "translating the title completes that language; changing the original outdates it" do
    page = create_page(title: "About")
    assert Pages::Save.call(page, translations: { "de" => { title: "Über" } }).ok?
    assert_equal "complete", state(page, "de").state
    assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
    assert_equal "outdated", state(page.reload, "de").state
    assert_equal 1, state(page, "de").outdated_count
    assert_equal 0, state(page, "de").missing_count
  end

  test "a block's fields count towards its page, and deleting the block takes them away" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    block = create_block(page, translations: { "en" => { body: rich_doc("The desk") } })
    assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Der Schreibtisch") } }).ok?
    assert_equal "complete", state(page, "de").state
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("The desk, changed") } }).ok?
    assert_equal "outdated", state(page, "de").state
    assert ContentBlocks::Destroy.call(block).ok?
    assert_equal "complete", state(page, "de").state
  end

  test "confirming an outdated field updates the row" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
    assert Translations::Confirm.call(page.reload, field: :title, locale: "de").ok?
    assert_equal "complete", state(page, "de").state
  end

  test "trashing keeps the rows, purging removes them" do
    page = create_page(title: "About")
    assert Trash::Move.call(page).ok?
    assert state(page, "de")
    assert Trash::Purge.call(page.reload).ok?
    assert_nil state(page, "de")
  end

  test "states_for answers in one query and treats a record with no row as complete" do
    pages = Array.new(3) { |i| create_page(title: "P#{i}") }
    Translations::State.where(record_type: "Page", record_id: pages.last.id).delete_all
    queries = count_queries { @states = Translations::StateIndex.states_for(pages) }
    assert_equal 1, queries
    assert_equal :missing, @states[pages.first]["de"]
    assert_equal :complete, @states[pages.last]["de"]
  end

  test "counts_for answers the field counts in one query" do
    page = create_page(title: "About")
    queries = count_queries { @counts = Translations::StateIndex.counts_for([ page ]) }
    assert_equal 1, queries
    assert_equal({ missing: 1, outdated: 0 }, @counts[page]["de"])
  end

  test "joins narrows a relation by state in one language" do
    done = create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
    create_page(title: "Todo")
    assert_equal [ done ], Translations::StateIndex.joins(Page.kept.where.not(parent_id: nil), locale: "de", states: %w[complete]).to_a
  end

  test "summary counts items, not fields" do
    create_page(title: "Done", translations: { "de" => { title: "Fertig" } })
    create_page(title: "Todo")
    summary = Translations::StateIndex.summary("de", [ Page.kept.where.not(parent_id: nil) ])
    assert_equal({ total: 2, complete: 1, missing: 1, outdated: 0 }, summary)
  end

  test "rebuild_all repairs rows that drifted and equals Translations::Status" do
    page = create_page(title: "About", translations: { "de" => { title: "Über" } })
    Translations::State.where(record_type: "Page", record_id: page.id).update_all(state: "missing")
    Translations::State.where(record_type: "Page", record_id: page.id, locale: "es").delete_all
    Translations::StateIndex.rebuild_all
    truth = Translations::Status.for([ page ])[page]
    assert_equal truth.transform_values(&:to_s), { "de" => state(page, "de").state, "es" => state(page, "es").state }
  end

  test "rebuild_all drops rows of records that no longer exist" do
    Translations::State.create!(record_type: "Page", record_id: 0, locale: "de", state: "missing")
    Translations::StateIndex.rebuild_all
    assert_nil Translations::State.find_by(record_type: "Page", record_id: 0)
  end

  test "Status.counts agrees with Status.for" do
    page = create_page(title: "About")
    counts = Translations::Status.counts([ page ])[page]
    assert_equal Translations::Status.for([ page ])[page], counts.transform_values { |c| c[:state] }
  end
end
