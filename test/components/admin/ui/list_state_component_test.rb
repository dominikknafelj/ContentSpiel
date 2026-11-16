require "test_helper"

class Admin::Ui::ListStateComponentTest < ViewComponent::TestCase
  def row(status:, published_at:, changes: false)
    Struct.new(:status, :published_at, :unpublished_changes?).new(status, published_at, changes)
  end

  test "a draft and a scheduled record show their chip, a live one none" do
    render_inline Admin::Ui::ListStateComponent.new(record: row(status: "draft", published_at: nil))
    assert_selector ".admin-status-chip[data-status=draft]", text: "Draft"

    render_inline Admin::Ui::ListStateComponent.new(record: row(status: "scheduled", published_at: 2.days.from_now))
    assert_selector ".admin-status-chip[data-status=scheduled]", text: "Scheduled"

    render_inline Admin::Ui::ListStateComponent.new(record: row(status: "live", published_at: 1.day.ago))
    assert_no_selector ".admin-status-chip"
    assert_no_selector "[data-unpublished-changes]"
    assert_equal "", rendered_content.strip
  end

  test "a live record with unpublished changes shows the unpublished chip and no Live chip; a draft with a stale mark shows Draft alone" do
    render_inline Admin::Ui::ListStateComponent.new(record: row(status: "live", published_at: 1.day.ago, changes: true))
    assert_selector "[data-unpublished-changes]", text: "Unpublished changes"
    assert_no_selector ".admin-status-chip"

    post = create_post(title: "Stale", published: false)
    post.update_columns(unpublished_changes_at: Time.current)
    render_inline Admin::Ui::ListStateComponent.new(record: post)
    assert_selector ".admin-status-chip[data-status=draft]"
    assert_no_selector "[data-unpublished-changes]"
  end

  test "it draws the shared chips' own markup" do
    at = 2.days.from_now
    record = row(status: "scheduled", published_at: at, changes: true)
    status = render_inline(Admin::Ui::StatusChipComponent.new(status: "scheduled", at: at, hide_live: true)).to_html
    unpublished = render_inline(Admin::Ui::UnpublishedChipComponent.new).to_html

    html = render_inline(Admin::Ui::ListStateComponent.new(record: record)).to_html
    assert_equal [ status, unpublished ].map { |h| h.gsub(/\s+/, " ").strip }.join(" "), html.gsub(/\s+/, " ").strip
  end

  test "a post of a switched-off type leads with the type's chip, then its own state; a live one shows the chip alone" do
    switch_on_content_types("blog")
    draft = create_post(title: "Resume", content_type: "blog", published: false)
    draft.update_columns(content_type: "resume_entry")
    live = create_post(title: "Live resume", content_type: "blog")
    live.update_columns(content_type: "resume_entry")

    html = render_inline(Admin::Ui::ListStateComponent.new(record: draft))
    assert_selector "[data-type-state=switched_off]", text: "Switched off"
    assert_selector ".admin-status-chip[data-status=draft]"
    assert_operator html.to_html.index("Switched off"), :<, html.to_html.index("Draft")

    render_inline Admin::Ui::ListStateComponent.new(record: live)
    assert_selector "[data-type-state=switched_off]", count: 1
    assert_no_selector ".admin-status-chip"
  end

  test "a post of a switched-on type draws no type chip" do
    render_inline Admin::Ui::ListStateComponent.new(record: create_post(title: "Draft", published: false))

    assert_no_selector "[data-type-state]"
  end
end
