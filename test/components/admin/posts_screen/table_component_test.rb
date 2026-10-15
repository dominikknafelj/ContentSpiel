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

  test "the list's script is told how many ids one request may ask about" do
    render_table([])

    assert_selector "[data-controller='admin--presence--list'][data-admin--presence--list-chunk-value='#{Presence::HERE_IDS}']"
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

  # Both features that mark a row, each read once for the page of posts
  # (presence plan, Review Focus 5).
  test "the table with notes and people on every post costs the same queries for 3 posts as for 30, and marks each row with both" do
    add = lambda do |count, prefix|
      Array.new(count) { |n| create_post(title: "#{prefix} #{n}") }.each do |post|
        as(users(:two)) { Notes::Start.call(post, body: "A note") }
        [ users(:two), users(:reader) ].each { |user| Presence::Mark.arrive(user:, record: post, tab: "tab-#{user.id}-1234567") }
      end
    end
    small_posts = add.(3, "Small")
    render_table(small_posts)
    small = count_queries { render_table(small_posts) }

    large_posts = small_posts + add.(27, "Large")
    large = count_queries { render_table(large_posts) }

    assert_selector "a[data-notes-count]", count: 30
    assert_selector "th[scope=row] a [data-presence-marker][data-presence-count='2']", count: 30
    assert_equal small, large, "the table ran a query per post"
  end

  test "an empty list reads nothing for its markers" do
    assert_equal 0, count_queries { Admin::PostsScreen::TableComponent.new(posts: [], paths: {}, translation_states: {}, locale: "en") }
  end

  test "with nothing registered after the title, the title line holds the title alone" do
    Admin::Slots.with("posts.row.title" => []) do
      render_table([ create_post(title: "Plain") ])
    end

    assert_no_selector "tbody th[scope=row] > :not(a)"
    assert_selector "tbody th[scope=row] > a > span:first-child > *", count: 1
  end

  # Presence handoff 27: the title's line is a row -- the title, cut with an
  # ellipsis before the marker is, then the marker 6px after it, inside the
  # link; the path line under it is as it was.
  test "the title's line is the title and then presence's marker, inside the link; the path line is unchanged" do
    busy = create_post(title: "Translating Everything With Mobility")
    quiet = create_post(title: "Quiet")
    [ users(:two), users(:reader) ].each { |user| Presence::Mark.arrive(user:, record: busy, tab: "tab-#{user.id}-1234567") }
    users(:two).update!(name: "Dana Weiss")

    render_table([ busy, quiet ], paths: { busy.id => "/blog/translating" })

    assert_selector "div[data-controller='admin--presence--list'][data-live-part=waiting][data-admin--presence--list-kind-value=post]" \
                    "[data-admin--presence--list-url-value='/cs-studio/presence/here?kind=post'] > table"
    link = "tr#post_#{busy.id} th[scope=row] > a.group\\/title.flex.min-w-0.flex-col.gap-0\\.5.text-ink.no-underline"
    assert_selector "#{link} > span", count: 2
    line = "#{link} > span:first-child"
    assert_equal %w[flex gap-1.5 items-center min-w-0], page.find(line)[:class].split.sort
    assert_selector "#{line} > span.min-w-0.truncate.font-medium:first-child", text: "Translating Everything With Mobility", exact_text: true
    assert_selector "#{line} > span.truncate + span[data-presence-marker='post-#{busy.id}'].flex-none.text-meta:not([hidden])[data-presence-count='2']"
    assert_selector "#{line} > [data-presence-marker] > span.sr-only", text: ", 2 people here: Dana Weiss, reader", exact_text: true
    assert_selector "#{link} > span.truncate.font-cs-mono.text-label.text-meta:last-child", text: "/blog/translating", exact_text: true
    # The hover underline is the title's and the path's own (review finding
    # 4): on the link it was drawn through everything in it, the marker's
    # count included, and a child cannot refuse a parent's underline.
    assert_no_selector "th[scope=row] > a.hover\\:underline"
    assert_selector "#{line} > span.truncate.group-hover\\/title\\:underline:first-child"
    assert_selector "#{link} > span.group-hover\\/title\\:underline:last-child"
    assert_no_selector "[data-presence-marker].group-hover\\/title\\:underline, [data-presence-marker] .group-hover\\/title\\:underline", visible: :all
    # Nothing interactive inside the link, and no Tab stop per row.
    assert_no_selector "th[scope=row] a a, th[scope=row] a button, th[scope=row] a [tabindex]", visible: :all
    # Nobody there: the marker's element, hidden, and nothing said.
    assert_selector "tr#post_#{quiet.id} th[scope=row] a > span:first-child > [data-presence-marker='post-#{quiet.id}'][hidden]", visible: :all
    assert_selector "tr#post_#{quiet.id} th[scope=row] a", text: /\A\s*Quiet\s*Not listed\s*\z/
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

  test "a live post with unpublished changes carries the chip in the Status column; a draft with a stale mark and a plain live post do not" do
    live = create_post(title: "Marked live")
    assert Posts::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    draft = create_post(title: "Marked draft", published: false)
    draft.update_columns(unpublished_changes_at: Time.current) # version: none (a test gives a draft a stale mark) # changes: none (a test gives a draft a stale mark)
    plain = create_post(title: "Plain live")

    render_table([ live.reload, draft.reload, plain ])

    assert_selector "tbody tr", count: 3
    assert_selector "[data-unpublished-changes]", count: 1
    assert_selector "tbody tr:has(th a[href*='/posts/#{live.id}']) td [data-unpublished-changes]", text: "Unpublished changes"
  end

  test "the table with marked posts costs the same queries for 3 posts as for 30" do
    add = lambda do |count, prefix|
      Array.new(count) { |n| create_post(title: "#{prefix} #{n}") }.each { |post| assert Posts::Save.call(post, translations: { "en" => { title: "#{post.title} typed" } }).ok? }
    end
    small_posts = add.(3, "Small").map(&:reload)
    render_table(small_posts)
    small = count_queries { render_table(small_posts) }

    large_posts = small_posts + add.(27, "Large").map(&:reload)
    large = count_queries { render_table(large_posts) }

    assert_selector "[data-unpublished-changes]", count: 30
    assert_equal small, large
  end
end
