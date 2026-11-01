require "test_helper"

# A Card's link to a page or post in CS Studio (#145): what a person who may
# not read the target is told, what is refused, and where the reference is
# never text.
class Admin::CardLinkTargetEditorTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @branch = create_page(title: "Branch")
    @holder = create_page(title: "Holder", parent: @branch)
    @inside = create_page(title: "Inside target", parent: @branch)
    @outside = create_page(title: "Outside target")
    %w[pages.read pages.edit pages.publish].each do |key|
      AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ @branch.id ] })
    end
    saved = ContentBlocks::Save.call(ContentBlock.new(owner: @holder),
      attributes: { block_type: "card", settings: { "link" => "cs:page/#{@outside.id}", "title" => "Card words" } })
    assert saved.ok?, saved.errors.to_sentence
    @card = saved.record
  end

  def save_link(link, title: "Card words")
    patch "/cs-studio/pages/#{@holder.id}/content_blocks/#{@card.id}",
      params: { block: { settings: { link: link, title: title } }, base_updated_at: @card.reload.updated_at.iso8601(6) }, as: :turbo_stream
  end

  test "a target outside the viewer's scope is not revealed in the editor, and they can still save the card" do
    sign_in_as(users(:editor_branch))
    get "/cs-studio/pages/#{@holder.id}"

    assert_response :success
    assert_not_includes response.body, "Outside target"
    assert_not_includes response.body, "outside-target"
    assert_select "[data-admin--ui--link-target-target=title]", text: I18n.t("admin.components.fields.link_field.unavailable")

    save_link("cs:page/#{@outside.id}", title: "New words")
    assert_response :success
    assert_equal "cs:page/#{@outside.id}", @card.reload.settings["link"]
  end

  test "a new reference outside the viewer's scope is refused like one to nothing, and writes nothing" do
    other = ContentBlocks::Save.call(ContentBlock.new(owner: @holder), attributes: { block_type: "card", settings: { "title" => "Second" } }).record
    sign_in_as(users(:editor_branch))
    answers = [ "cs:page/#{@outside.id}", "cs:page/999999", "cs:page/nonsense" ].map do |link|
      patch "/cs-studio/pages/#{@holder.id}/content_blocks/#{other.id}",
        params: { block: { settings: { link: link, title: "Second" } }, base_updated_at: other.reload.updated_at.iso8601(6) }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_nil other.reload.settings["link"]
      response.body.gsub(/<input[^>]*>/, "").gsub(link, "").gsub(/value="[^"]*"/, "")
    end
    assert_not_includes answers.first, "Outside target"

    patch "/cs-studio/pages/#{@holder.id}/content_blocks/#{other.id}",
      params: { block: { settings: { link: "cs:page/#{@inside.id}", title: "Second" } }, base_updated_at: other.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "cs:page/#{@inside.id}", other.reload.settings["link"]
  end

  test "the picker offers only what the person may read" do
    sign_in_as(users(:editor_branch))
    get "/cs-studio/link_targets", params: { q: "target", locale: "en" }

    assert_equal [ @inside.id ], response.parsed_body.map { |row| row["id"] }
  end

  test "the reference is no text on the tile, on a translation tab or in the audit log" do
    sign_in_as(users(:one))
    Locales::Enable.call("de") unless Locales.enabled?("de")
    get "/cs-studio/pages/#{@holder.id}"
    assert_response :success
    assert_select "[data-admin--ui--link-target-target=title]", text: "Outside target"
    assert_no_visible_reference

    get "/cs-studio/pages/#{@holder.id}", params: { locale: "de" }
    assert_response :success
    assert_select "details[data-shared-fields]", text: /Outside target/
    assert_no_visible_reference

    as_owner do
      assert ContentBlocks::Save.call(@card.reload, attributes: { settings: { "link" => "cs:page/#{@inside.id}", "title" => "Card words" } }).ok?
    end
    get "/cs-studio/audit_events"
    assert_response :success
    assert_no_visible_reference
    event = Audit::Event.where(action: "block.updated").order(:id).last
    assert event, "the save was audited"
    assert_not_includes event.field_changes.to_json, "cs:page"
    get "/cs-studio/audit_events/#{event.id}"
    assert_response :success
    assert_no_visible_reference
  end

  # A reference is a form's value and nothing else: no text node holds it. The
  # one exception is the audit event's collapsed "Snapshot", which says it is
  # the raw record, as it does for a body's document.
  def assert_no_visible_reference
    assert_empty Nokogiri::HTML5(response.body).xpath("//body//text()[not(ancestor::script) and not(ancestor::pre)]").map(&:text).grep(/cs:(page|post)/)
  end

  test "a duplicate and a discard carry the reference, a duplicate by someone who can't read the target included" do
    sign_in_as(users(:editor_branch))
    copy = as(users(:editor_branch)) { ContentBlocks::Duplicate.call(@card) }
    assert copy.ok?, copy.errors.to_sentence
    duplicated = @holder.content_blocks.where.not(id: @card.id).first
    assert_equal "cs:page/#{@outside.id}", duplicated.settings["link"]

    publish_changes(@holder)
    other = ContentBlocks::Save.call(@card.reload, attributes: { settings: { "link" => "/elsewhere", "title" => "Card words" } })
    assert other.ok?, other.errors.to_sentence
    discarded = Publishing::DiscardChanges.call(@holder.reload)
    assert discarded.ok?, discarded.errors.to_sentence
    assert_equal "cs:page/#{@outside.id}", @card.reload.settings["link"]
  end
end
