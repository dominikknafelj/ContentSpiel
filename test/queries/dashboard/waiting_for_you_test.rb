require "test_helper"

class Dashboard::WaitingForYouTest < ActiveSupport::TestCase
  setup { @base = Time.current.change(usec: 0) }

  def note(subject, at: @base) = travel_to(at) { as(users(:one)) { Notes::Start.call(subject, body: "A note") }.record }

  def mark(record, at) = record.update_columns(unpublished_changes_at: at)

  def waiting(actor = users(:two), filter: "everything") = Dashboard::WaitingForYou.new(actor:, filter:, channel: :admin)

  def summary(rows) = rows.map { |row| [ row.record, row.reasons ] }

  test "threads and unpublished changes in one list, the newest first, cut to five" do
    discussed = Array.new(4) { |n| create_page(title: "Discussed #{n}") }
    marked = Array.new(4) { |n| create_post(title: "Marked #{n}") }
    discussed.each_with_index { |page, n| note(page, at: @base + (2 * n + 1).minutes) }
    marked.each_with_index { |post, n| mark(post, @base + (2 * n + 2).minutes) }

    rows = waiting.rows

    assert_equal [ [ marked[3], [ :unpublished ] ], [ discussed[3], [ :thread ] ], [ marked[2], [ :unpublished ] ],
                   [ discussed[2], [ :thread ] ], [ marked[1], [ :unpublished ] ] ], summary(rows)
    assert_equal [ 8, 7, 6, 5, 4 ].map { |minutes| @base + minutes.minutes }, rows.map(&:at)
    assert rows.all? { |row| row.reasons.frozen? }
  end

  test "a discussed and unpublished record is one row carrying both reasons, and found under both filters" do
    page = create_page(title: "Both")
    note(page, at: @base + 1.minute)
    note(page, at: @base + 2.minutes)
    mark(page, @base + 3.minutes)

    row = waiting.rows.sole
    assert_equal [ page, [ :thread, :unpublished ] ], [ row.record, row.reasons ]
    assert_equal 2, row.thread.count
    assert_equal [ @base + 3.minutes, @base + 3.minutes ], [ row.at, row.unpublished_at ]
    assert_equal({ notes: "open" }, row.route.params)

    threads = waiting(filter: "threads").rows.sole
    assert_equal [ page, [ :thread ], nil, nil, @base + 2.minutes ], [ threads.record, threads.reasons, threads.unpublished_at, threads.review_route, threads.at ]

    unpublished = waiting(filter: "unpublished").rows.sole
    assert_equal [ page, [ :unpublished ], nil, @base + 3.minutes ], [ unpublished.record, unpublished.reasons, unpublished.thread, unpublished.at ]
    assert_equal Audit::Sentence.route_for(page), unpublished.route
  end

  test "a row completes the reason its source did not bring" do
    newer_thread = create_page(title: "Thread newer")
    others = Array.new(5) { |n| create_post(title: "Marked #{n}") }
    others.each_with_index { |post, n| mark(post, @base + (n + 1).minutes) }
    mark(newer_thread, @base)
    note(newer_thread, at: @base + 10.minutes)

    row = waiting.rows.first
    assert_equal [ newer_thread, [ :thread, :unpublished ], @base, @base + 10.minutes ], [ row.record, row.reasons, row.unpublished_at, row.at ]
    assert_not_nil row.review_route

    newer_mark = create_post(title: "Mark newer")
    others.each { |post| post.update_columns(unpublished_changes_at: nil) }
    newer_thread.update_columns(unpublished_changes_at: nil)
    note(newer_mark, at: @base)
    Array.new(5) { |n| create_page(title: "Discussed #{n}") }.each_with_index { |page, n| note(page, at: @base + (n + 1).minutes) }
    mark(newer_mark, @base + 20.minutes)

    row = waiting.rows.first
    assert_equal [ newer_mark, [ :thread, :unpublished ], @base + 20.minutes ], [ row.record, row.reasons, row.at ]
    assert_equal [ 1, @base ], [ row.thread.count, row.thread.at ]
    assert_equal({ notes: "open" }, row.route.params)
  end

  test "each filter reads its own source alone, and an unknown filter is everything" do
    discussed = create_page(title: "Discussed")
    note(discussed)
    marked = create_post(title: "Marked")
    mark(marked, @base)

    threads = nil
    statements = capture_sql { threads = waiting(filter: "threads").rows }
    assert_equal [ [ discussed, [ :thread ] ] ], summary(threads)
    assert_empty statements.grep(/unpublished_changes_at/)

    unpublished = nil
    statements = capture_sql { unpublished = waiting(filter: "unpublished").rows }
    assert_equal [ [ marked, [ :unpublished ] ] ], summary(unpublished)
    assert_empty statements.grep(/note_threads/)

    [ "junk", "", nil ].each do |filter|
      query = waiting(filter:)
      assert_equal "everything", query.filter
      assert_equal [ discussed, marked ].to_set, query.rows.map(&:record).to_set
    end
    assert_equal Dashboard::WaitingForYou::FILTERS, Dashboard::WaitingForYou::FILTERS.map { |filter| waiting(filter:).filter }
  end

  test "a row offers review only to a viewer who may publish it" do
    page = create_page(title: "Marked")
    mark(page, @base)
    editors = AccessControl::Group.create!(name: "Page editors")
    %w[pages.read pages.edit].each { |permission| editors.grants.create!(permission:, scope: {}) }
    editor = User.create!(email_address: "page-editor@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(user: editor, group: editors)

    row = waiting(editor).rows.sole
    assert_equal [ page, nil, Audit::Sentence.route_for(page) ], [ row.record, row.review_route, row.route ]

    review = waiting(users(:two)).rows.sole.review_route
    assert_equal [ :admin_page_path, [ page.id ], { review: "publish" } ], [ review.name, review.args, review.params ]
  end

  test "what the viewer may not read and what is in the trash leave no row" do
    kept = create_page(title: "Kept")
    binned = create_page(title: "Binned")
    blog = create_post(title: "Blog")
    resume = create_post(title: "Resume", content_type: "resume_entry")
    [ kept, binned ].each { |page| mark(page, @base) }
    [ blog, resume ].each { |post| note(post) }
    as(users(:one)) { assert Trash::Move.call(binned).ok? }
    readers = AccessControl::Group.create!(name: "Blog and page readers")
    readers.grants.create!(permission: "pages.read", scope: {})
    readers.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    reader = User.create!(email_address: "scoped-reader@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(user: reader, group: readers)

    assert_equal [ kept, blog ].to_set, waiting(reader).rows.map(&:record).to_set
    assert_equal [ blog ], waiting(reader, filter: "threads").rows.map(&:record)
    assert_equal [ kept ], waiting(reader, filter: "unpublished").rows.map(&:record)
    assert_equal [ kept, blog, resume ].to_set, waiting(users(:two)).rows.map(&:record).to_set
  end

  test "a page and a post with the same id and the same time are ranked by their model, at the cut and in the order" do
    page = create_page(title: "Same id")
    post = create_post(title: "Same id")
    Post.where(id: post.id).update_all(id: page.id) if post.id != page.id
    post = Post.find(page.id)
    [ page, post ].each { |record| mark(record, @base) }
    newer = Array.new(3) { |n| create_post(title: "Newer #{n}") }
    newer.each_with_index { |record, n| mark(record, @base + (n + 1).minutes) }

    assert_equal [ post, page ], waiting.rows.last(2).map(&:record)
    assert_equal [ post, page ], waiting(filter: "unpublished").rows.last(2).map(&:record)

    mark(create_post(title: "Newest"), @base + 10.minutes)
    assert_equal post, waiting.rows.last.record
    assert_not_includes waiting.rows.map(&:record), page
  end

  test "the total counts every record under the filter, beyond the five rows, a record with both reasons once" do
    discussed = Array.new(6) { |n| create_page(title: "Discussed #{n}") }
    marked = Array.new(2) { |n| create_post(title: "Marked #{n}") }
    discussed.each_with_index { |page, n| note(page, at: @base + n.minutes) }
    marked.each { |post| mark(post, @base) }
    mark(discussed.first, @base)
    binned = create_post(title: "Binned")
    mark(binned, @base)
    as(users(:one)) { assert Trash::Move.call(binned).ok? }

    assert_equal [ 8, 6, 3 ], %w[everything threads unpublished].map { |filter| waiting(filter:).total }
    assert_equal 5, waiting.rows.size
    nobody = User.create!(email_address: "none@example.com", password: "a-long-password-1")
    assert_equal [ 0, 0, 0 ], %w[everything threads unpublished].map { |filter| waiting(nobody, filter:).total }
  end

  test "the same statements for one row of each as for five" do
    pages = Array.new(5) { |n| create_page(title: "Discussed #{n}") }
    posts = Array.new(5) { |n| create_post(title: "Marked #{n}") }
    note(pages.first, at: @base + 1.minute)
    mark(posts.first, @base + 2.minutes)
    waiting.rows # warm-up: the fixture user's grants are read once and kept on the object
    few = count_statements { assert_equal 2, waiting.rows.size }

    pages.drop(1).each_with_index { |page, n| note(page, at: @base + (2 * n + 3).minutes) }
    posts.drop(1).each_with_index { |post, n| mark(post, @base + (2 * n + 4).minutes) }

    rows = nil
    many = count_statements { rows = waiting.rows }
    assert_equal 5, rows.size
    assert_equal [ :thread, :unpublished ].to_set, rows.flat_map(&:reasons).to_set
    assert_equal few, many
  end
end
