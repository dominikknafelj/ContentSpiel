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
end
