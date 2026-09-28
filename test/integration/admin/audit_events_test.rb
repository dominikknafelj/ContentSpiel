require "test_helper"

# The audit log module (design spec §5 "Audit log module", Task 9): access,
# filters, pagination, the event page, and subject links. What each service
# actually records is covered by test/services/audit_events_test.rb -- this
# covers the screens that read `Audit::Event` back.
class Admin::AuditEventsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "needs audit.view -- an author gets 403" do
    sign_in_as(users(:author))
    get "/cs-studio/audit_events"
    assert_response :forbidden
  end

  test "the list is newest first, and the sidebar links to it" do
    sign_in_as(users(:one))
    older = travel_to(2.days.ago) { as(users(:one)) { create_post(title: "Older post", published: false) } }
    newer = as(users(:one)) { create_post(title: "Newer post", published: false) }

    get "/cs-studio/audit_events"

    assert_response :success
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/audit_events']", text: "Audit log"

    body = response.body
    newer_event = Audit::Event.find_by!(action: "post.created", subject: newer)
    older_event = Audit::Event.find_by!(action: "post.created", subject: older)
    assert_operator body.index(dom_id(newer_event)), :<, body.index(dom_id(older_event)),
      "expected the newer event to render before the older one"
  end

  test "filters by user" do
    sign_in_as(users(:one))
    mine = as(users(:one)) { create_post(title: "By owner", published: false) }
    theirs = as(users(:two)) { create_post(title: "By admin two", published: false) }

    get "/cs-studio/audit_events", params: { user_id: users(:two).id }

    assert_response :success
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: theirs))}"
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: mine))}", count: 0
  end

  test "filters by action" do
    sign_in_as(users(:one))
    post_record = as(users(:one)) { create_post(title: "Filtered by action", published: false) }
    page_record = as(users(:one)) { create_page(title: "Filtered out") }

    get "/cs-studio/audit_events", params: { event_action: "post.created" }

    assert_response :success
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: post_record))}"
    assert_select "##{dom_id(Audit::Event.find_by!(action: "page.created", subject: page_record))}", count: 0
  end

  test "filters by subject type and subject" do
    sign_in_as(users(:one))
    post_a = as(users(:one)) { create_post(title: "Post A", published: false) }
    post_b = as(users(:one)) { create_post(title: "Post B", published: false) }

    get "/cs-studio/audit_events", params: { subject_type: "Post", subject_id: post_a.id }

    assert_response :success
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: post_a))}"
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: post_b))}", count: 0
  end

  test "an unknown subject type is ignored rather than erroring" do
    sign_in_as(users(:one))
    get "/cs-studio/audit_events", params: { subject_type: "NotARealModel" }
    assert_response :success
  end

  test "filters by date range" do
    sign_in_as(users(:one))
    in_range = travel_to(Date.new(2026, 6, 15)) { as(users(:one)) { create_post(title: "In range", published: false) } }
    out_of_range = travel_to(Date.new(2026, 1, 1)) { as(users(:one)) { create_post(title: "Out of range", published: false) } }

    get "/cs-studio/audit_events", params: { from: "2026-06-01", to: "2026-06-30" }

    assert_response :success
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: in_range))}"
    assert_select "##{dom_id(Audit::Event.find_by!(action: "post.created", subject: out_of_range))}", count: 0
  end

  test "a malformed date filter is ignored, not a 500" do
    sign_in_as(users(:one))
    get "/cs-studio/audit_events", params: { from: "not-a-date", to: "also-not-a-date" }
    assert_response :success
  end

  test "paginates 50 per page, with Next and Previous" do
    sign_in_as(users(:one))
    51.times do |n|
      Audit::Event.create!(action: "test.paginate", subject_label: "Item #{n}", channel: "admin",
        occurred_at: (51 - n).minutes.ago, last_occurred_at: (51 - n).minutes.ago)
    end

    get "/cs-studio/audit_events", params: { event_action: "test.paginate" }
    assert_response :success
    assert_select "tbody tr", 50
    assert_select "a", { text: "Next" }
    assert_select "a", { text: "Previous", count: 0 }

    get "/cs-studio/audit_events", params: { event_action: "test.paginate", offset: 50 }
    assert_response :success
    assert_select "tbody tr", 1
    assert_select "a", { text: "Next", count: 0 }
    assert_select "a", { text: "Previous" }
  end

  test "the event page renders field changes and an escaped snapshot" do
    sign_in_as(users(:one))
    post_record = as(users(:one)) { create_post(title: "<script>alert(1)</script>", published: false) }
    event = Audit::Event.find_by!(action: "post.created", subject: post_record)

    get "/cs-studio/audit_events/#{event.id}"

    assert_response :success
    assert_select "table" # the changes table
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert(1)</script>"
  end

  test "a rich-text body change renders as Changed, not raw digests" do
    sign_in_as(users(:one))
    page = as(users(:one)) { create_page(title: "Body change") }
    block = as(users(:one)) { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record }
    as(users(:one)) { ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Hello there") } }) }
    event = Audit::Event.find_by!(action: "block.updated", subject: block)

    get "/cs-studio/audit_events/#{event.id}"

    assert_response :success
    assert_select "table", text: /Changed/
  end

  test "a deleted subject's event shows the label without a link" do
    sign_in_as(users(:one))
    page = as(users(:one)) { create_page(title: "Temporary page") }
    label = page.title
    as(users(:one)) { Pages::Destroy.call(page) }
    event = Audit::Event.find_by!(action: "page.deleted", subject_type: "Page", subject_id: page.id)

    get "/cs-studio/audit_events"

    assert_response :success
    assert_select "##{dom_id(event)}" do
      assert_select "a", text: label, count: 0
    end
    assert_select "##{dom_id(event)}", text: /#{Regexp.escape(label)}/
  end

  test "a subject link only renders when the current viewer can read that record" do
    group = AccessControl::Group.create!(name: "Audit only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "audit.view")
    viewer = User.create!(email_address: "audit-only@example.com", password: "password", password_confirmation: "password")
    AccessControl::Membership.create!(user: viewer, group: group)

    post_record = as(users(:one)) { create_post(title: "Gated post", published: false) }
    event = Audit::Event.find_by!(action: "post.created", subject: post_record)

    sign_in_as(viewer)
    get "/cs-studio/audit_events/#{event.id}"

    assert_response :success
    assert_select "dd a", text: post_record.title, count: 0
    assert_select "dd", text: /#{Regexp.escape(post_record.title)}/
  end

  test "the post editor's Activity link opens the log filtered to that post, and the page editor's own" do
    sign_in_as(users(:one))
    post_record = as(users(:one)) { create_post(title: "Linked post", published: false) }
    page = as(users(:one)) { create_page(title: "Linked page") }

    get "/cs-studio/posts/#{post_record.id}"
    assert_select "a[href*='subject_type=Post'][href*='subject_id=#{post_record.id}']", text: "Activity"

    get "/cs-studio/pages/#{page.id}"
    assert_select "a[href*='subject_type=Page'][href*='subject_id=#{page.id}']", text: "Activity"

    get "/cs-studio/audit_events", params: { subject_type: "Page", subject_id: page.id }
    assert_response :success
    assert_select "##{dom_id(Audit::Event.find_by!(action: "page.created", subject: page))}"
  end

  test "the user editor's Activity link opens the log filtered to that user" do
    sign_in_as(users(:one))

    get "/cs-studio/users/#{users(:two).id}/edit"

    assert_select "a[href*='subject_type=User'][href*='subject_id=#{users(:two).id}']", text: "Activity"
  end

  test "the Activity link is absent without audit.view" do
    sign_in_as(users(:author))
    # `users(:author)` may edit their own posts (Author group, design spec
    # §5 "Seeded groups") but holds no `audit.view` -- the editor renders
    # for them fine, just without the link.
    own_post = as(users(:author)) { create_post(title: "Author's own", published: false) }

    get "/cs-studio/posts/#{own_post.id}"

    assert_response :success
    assert_select "a", text: "Activity", count: 0
  end

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)
end
