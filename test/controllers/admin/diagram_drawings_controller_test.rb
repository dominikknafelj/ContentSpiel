require "test_helper"
require_relative "../../support/diagram_fixtures"

# Saving one Diagram block's drawing for one language from the Draw diagrams
# task (draw-diagrams spec §4): the block found through the read scope, a
# stale base, a hold in another tab and a source changed since the list was
# drawn are refused before anything is written; the save is the block card's
# own (`ContentBlocks::Save`), and the answer is JSON for the list's script.
class Admin::DiagramDrawingsControllerTest < ActionDispatch::IntegrationTest
  EN = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")
  DE = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("de")
  RAW = DiagramFixtures::DIR.join("flowchart.svg").read
  SCRIPT = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><script>alert(1)</script></svg>'
  TAB = "tab-aaaaaaaa".freeze
  OTHER_TAB = "tab-bbbbbbbb".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Flows", published: false)
  end

  def diagram(page = @page, source: EN)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => source } } }, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def stored_source(block, locale = "en") = block.reload.translated_settings.dig(locale, "source")

  def save_drawing(block, svg: RAW, locale: "en", from: Diagrams::Drawing.digest(stored_source(block, locale)),
    base: block.reload.updated_at.iso8601(6), tab: TAB)
    patch admin_diagram_drawing_path(block), headers: { "X-Notes-Tab" => tab }.compact,
      params: { locale: locale, svg: svg, from: from, base_updated_at: base }
  end

  def answer = response.parsed_body

  def editor_without_publish
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: {}) }
    users(:editor_branch)
  end

  test "a drawing is saved and audited" do
    block = diagram
    sign_in_as users(:one)
    from = Diagrams::Drawing.digest(stored_source(block))

    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      save_drawing(block)
    end

    assert_response :ok
    assert_equal({ "svg" => Diagrams::Drawing.clean(RAW).svg, "from" => from }, block.reload.translated_settings.dig("en", "drawing"))
    assert_equal({ "ok" => true, "live" => false, "page_id" => @page.id, "page_title" => "Flows",
                   "review_url" => admin_page_path(@page, review: "publish") }, answer)
    assert_equal users(:one).id, Audit::Event.where(action: "block.updated").last.actor_id
  end

  test "a drawing in a second language is saved for that language alone" do
    block = diagram
    ContentBlocks::Save.call(block, translations: { "de" => { settings: { "source" => DE } } }, actor: users(:one))
    sign_in_as users(:one)

    save_drawing(block, locale: "de")

    assert_response :ok
    assert_equal Diagrams::Drawing.digest(stored_source(block, "de")), block.reload.translated_settings.dig("de", "drawing", "from")
    assert_nil block.translated_settings.dig("en", "drawing")
  end

  test "a live page answers live with its review url" do
    live = create_page(title: "Live", published: true)
    block = diagram(live)
    sign_in_as users(:one)

    save_drawing(block)

    assert_response :ok
    assert_equal true, answer["live"]
    assert answer["review_url"].end_with?("?review=publish"), answer["review_url"]
    assert_equal admin_page_path(live, review: "publish"), answer["review_url"]
  end

  test "a block outside the scope is gone" do
    other = create_page(title: "Other", published: false)
    block = diagram(other)
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: { "page_ids" => [ @page.id ] }) }
    sign_in_as users(:editor_branch)

    assert_no_difference -> { Audit::Event.count } do
      save_drawing(block)
    end

    assert_response :not_found
    assert_equal({ "ok" => false, "reason" => "gone", "holder" => nil }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "a block that is not a diagram is gone" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }, actor: users(:one)).record
    sign_in_as users(:one)

    save_drawing(block, from: Diagrams::Drawing.digest(EN))

    assert_response :not_found
    assert_equal "gone", answer["reason"]
  end

  test "a stale base is refused" do
    block = diagram
    base = block.updated_at.iso8601(6)
    travel 1.second
    ContentBlocks::Save.call(block, translations: { "en" => { settings: { "description" => "Changed elsewhere" } } }, actor: users(:two))
    sign_in_as users(:one)

    assert_no_difference -> { Audit::Event.count } do
      save_drawing(block, base: base)
    end

    assert_response :conflict
    assert_equal({ "ok" => false, "reason" => "stale", "holder" => nil }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "a block held in another tab is refused with the holder, and no claim is taken" do
    block = diagram
    reserve(block, @page, users(:two), OTHER_TAB)
    sign_in_as users(:one)

    assert_no_difference -> { Audit::Event.count } do
      save_drawing(block)
    end

    assert_response :conflict
    assert_equal({ "ok" => false, "reason" => "held", "holder" => PersonName.of(users(:two)) }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
    assert_equal [ [ users(:two).id, OTHER_TAB ] ], Editing::Reservation.pluck(:user_id, :tab)
  end

  test "a save takes no claim of a block nobody holds" do
    block = diagram
    sign_in_as users(:one)

    save_drawing(block)

    assert_response :ok
    assert_empty Editing::Reservation.all
  end

  test "a from that is not the stored source is refused" do
    block = diagram
    sign_in_as users(:one)

    [ Diagrams::Drawing.digest(DE), "", nil ].each do |from|
      assert_no_difference -> { Audit::Event.count } do
        save_drawing(block, from: from)
      end

      assert_response :conflict
      assert_equal({ "ok" => false, "reason" => "changed", "holder" => nil }, answer, from.inspect)
    end

    save_drawing(block, locale: "de", from: Diagrams::Drawing.digest(EN))
    assert_response :conflict
    assert_equal "changed", answer["reason"], "a language with no source of its own has nothing to draw"
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "a drawing that does not clean is refused" do
    block = diagram
    sign_in_as users(:one)

    save_drawing(block, svg: SCRIPT)

    assert_response :unprocessable_entity
    assert_equal({ "ok" => false, "reason" => "invalid_drawing", "holder" => nil }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "a drawing over the limit is refused" do
    block = diagram
    sign_in_as users(:one)
    words = "a" * (Diagrams::Drawing::MAX_BYTES + 1)
    large = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><text>#{words}</text></svg>)
    assert_equal :too_large, Diagrams::Drawing.clean(large).reason, "the sample is refused as too large"

    save_drawing(block, svg: large)

    assert_response :unprocessable_entity
    assert_equal({ "ok" => false, "reason" => "too_large", "holder" => nil }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "no publish right on a live page is denied" do
    live = create_page(title: "Live", published: true)
    block = diagram(live)
    sign_in_as editor_without_publish

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      save_drawing(block)
    end

    assert_response :forbidden
    assert_equal({ "ok" => false, "reason" => "denied", "holder" => nil }, answer)
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "nothing is published" do
    live = create_page(title: "Live", published: true)
    block = diagram(live)
    publish_changes(live)
    copies = Publishing::Version.of(live).pluck(:id, :blocks)
    sign_in_as users(:one)

    save_drawing(block)

    assert_response :ok
    assert_equal copies, Publishing::Version.of(live).pluck(:id, :blocks)
    assert live.reload.unpublished_changes?, "the drawing waits for Publish changes"
  end

  test "it needs pages.edit" do
    block = diagram
    sign_in_as users(:reader)

    save_drawing(block)

    assert_response :forbidden
    assert_equal "application/json", response.media_type
    assert_nil block.reload.translated_settings.dig("en", "drawing")
  end

  test "the CSRF check stays on" do
    block = diagram
    sign_in_as users(:one)

    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference -> { Audit::Event.where(action: "block.updated").count } do
      save_drawing(block)
    end

    assert_nil block.reload.translated_settings.dig("en", "drawing")
  ensure
    ActionController::Base.allow_forgery_protection = before
  end
end
