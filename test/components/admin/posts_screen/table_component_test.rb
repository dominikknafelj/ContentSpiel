require "test_helper"

class Admin::PostsScreen::TableComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  def render_table(posts, paths: {}, states: nil, **options)
    states ||= posts.index_with { { "de" => :missing, "es" => :outdated } }
    render_inline Admin::PostsScreen::TableComponent.new(posts:, paths:, translation_states: states, **options) do |table|
      table.with_footer { "FOOTER" }
    end
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  test "the table with open notes costs the same queries for 3 posts as for 30, and draws a pill on each" do
    add = lambda do |count, prefix|
      Array.new(count) { |n| create_post(title: "#{prefix} #{n}") }.each { |post| as(users(:two)) { Notes::Start.call(post, body: "A note") } }
    end
    small_posts = add.(3, "Small")
    render_table(small_posts)
    small = count_queries { render_table(small_posts) }

    large_posts = small_posts + add.(27, "Large")
    large = count_queries { render_table(large_posts) }

    assert_selector "a[data-notes-count]", count: 30
    assert_equal small, large, "the table ran a notes query per post"
  end

  test "an empty slot after the title draws nothing" do
    render_table([ create_post(title: "Plain") ])

    assert_no_selector "tbody th[scope=row] > :not(a)"
  end

  test "the columns, a checkbox per row, and the select-all header checkbox" do
    draft = create_post(title: "A draft", published: false)
    render_table([ draft ])
    assert_selector "thead th", text: /Title/
    %w[Type Status Translations Updated].each { |name| assert_selector "thead th", text: /#{name}/ }
    assert_selector "thead input.cs-checkbox[data-admin--posts--bulk-select-target=all][aria-label='Select all posts on this page']"
    assert_selector "tbody tr#post_#{draft.id} input.cs-checkbox[data-admin--posts--bulk-select-target=row][value='#{draft.id}'][aria-label='Select A draft']"
    assert_text "FOOTER"
  end

  # Review C, M7 and M16.
  test "a viewer who can neither publish nor trash gets no selection column" do
    post_record = create_post(title: "Readable")
    Current.actor = users(:reader)
    render_table([ post_record ])
    assert_no_selector "input[type=checkbox]"
    assert_no_selector "[data-admin--posts--bulk-select-target]"
    assert_selector "tbody tr#post_#{post_record.id} th[scope=row] a", text: /Readable/
  end

  test "column headers are scoped, the title is the row header, and the sort is announced without the arrow glyph" do
    render_table([ create_post(title: "A draft", published: false) ])
    assert_selector "thead th[scope=col]", minimum: 6
    assert_no_selector "thead th:not([scope])"
    assert_selector "thead th[aria-sort=descending]", text: /\AUpdated/
    assert_selector "thead th[aria-sort=descending] span[aria-hidden=true]", text: "↓"
    assert_selector "tbody th[scope=row]", count: 1
  end

  test "title links to the editor with its path under it, or Not listed" do
    listed = create_post(title: "Listed")
    unlisted = create_post(title: "Unlisted")
    render_table([ listed, unlisted ], paths: { listed.id => "/blog/listed" })
    assert_selector "a[href='/cs-studio/posts/#{listed.id}']", text: /Listed\s*\/blog\/listed/
    assert_selector "a[href='/cs-studio/posts/#{unlisted.id}']", text: /Unlisted\s*Not listed/
  end

  test "Live draws no status chip; a draft and a scheduled post do" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one", published: false)
    render_table([ live, draft ])
    assert_selector "tr#post_#{draft.id} .admin-status-chip", text: "Draft"
    assert_no_selector "tr#post_#{live.id} .admin-status-chip"
  end

  test "each language chip links to that language's editor tab" do
    post = create_post(title: "Chips")
    render_table([ post ])
    assert_selector "a[href='/cs-studio/posts/#{post.id}?locale=de'] .admin-translation-chip[data-translation-state=missing]"
    assert_selector "a[href='/cs-studio/posts/#{post.id}?locale=es'] .admin-translation-chip[data-translation-state=outdated]"
  end

  test "the row menu: Open, View on site only while live and listed, Move to trash where permitted" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one", published: false)
    render_table([ live, draft ], paths: { live.id => "/blog/live-one", draft.id => "/blog/draft-one" })
    assert_selector "tr#post_#{live.id} [role=menu] a", text: "Open", visible: :all
    assert_selector "tr#post_#{live.id} [role=menu] a[href='/blog/live-one']", text: "View on site", visible: :all
    assert_no_selector "tr#post_#{draft.id} [role=menu] a", text: "View on site", visible: :all
    assert_selector "tr#post_#{draft.id} [role=menu] button[data-action='admin--posts--bulk-select#only admin--ui--dialog#open'][data-admin--posts--bulk-select-id-param='#{draft.id}'][data-admin--ui--dialog-id-param=bulk-trash-dialog]", text: "Move to trash", visible: :all
    assert_no_selector "tr#post_#{draft.id} form", visible: :all
    assert_selector "tr#post_#{draft.id} button[aria-label='Actions for Draft one']"

    Current.actor = users(:reader)
    render_table([ draft ])
    assert_no_selector "[role=menu] button", text: "Move to trash", visible: :all
  end
end
