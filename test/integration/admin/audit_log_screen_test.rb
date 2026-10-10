require "test_helper"

# The audit log's list and event page as redesigned in round 3, Task 15: day
# headers in the site's time zone, coalesced spans, the filter row with date
# presets, human sentences, the event page's word diffs and Older/Newer.
# (`audit_events_test.rb` keeps access, the older filters, disclosure and the
# editors' Activity links.)
class Admin::AuditLogScreenTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current, time_zone: "Europe/Berlin")
    @me = users(:one)
    sign_in_as(@me)
  end

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  def event(at, last: at, **attributes)
    Audit::Event.create!({ action: "test.screen", channel: "admin", user_id: @me.id, subject_label: "Thing",
      occurred_at: at, last_occurred_at: last }.merge(attributes))
  end

  def headers = css_select("section[aria-labelledby^=audit-day] h2").map { |node| node.text.strip }

  # --- day headers -------------------------------------------------------------

  test "events sit under Today, Yesterday and a dated header, by the site's calendar" do
    # 22:30 UTC on 3 Oct is 00:30 on 4 Oct in Berlin (CEST): still "Today" there.
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      today = event(Time.utc(2026, 10, 3, 22, 30))
      yesterday = event(Time.utc(2026, 10, 3, 20, 0)) # 22:00 on the 3rd, Berlin
      older = event(Time.utc(2026, 9, 29, 9, 0))
      last_year = event(Time.utc(2025, 12, 24, 9, 0))

      get "/cs-studio/audit_events", params: { event_action: "test.screen" }

      assert_equal [ "Today", "Yesterday", "Tue 29 Sep", "Wed 24 Dec 2025" ], headers
      assert_select "section:nth-of-type(1) ##{dom_id(today)}"
      assert_select "section:nth-of-type(2) ##{dom_id(yesterday)}"
      assert_select "section:nth-of-type(3) ##{dom_id(older)}"
      assert_select "section:nth-of-type(4) ##{dom_id(last_year)}"
      assert_select "##{dom_id(today)} a", text: "00:30"
    end
  end

  test "a coalesced span shows both ends, sits under the day it ended, and is one row" do
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      same_day = event(Time.utc(2026, 10, 3, 14, 5), last: Time.utc(2026, 10, 3, 14, 31), occurrences: 12, action: "test.screen")
      overnight = event(Time.utc(2026, 10, 3, 21, 50), last: Time.utc(2026, 10, 3, 22, 10), action: "test.screen")

      get "/cs-studio/audit_events", params: { event_action: "test.screen" }

      assert_select "##{dom_id(same_day)} a", text: "16:05–16:31"
      # 23:50 Sat -> 00:10 Sun in Berlin: the start names its day.
      assert_select "##{dom_id(overnight)} a", text: "Sat 23:50–00:10"
      assert_equal [ "Today", "Yesterday" ], headers
      assert_select "section:nth-of-type(1) ##{dom_id(overnight)}"
      assert_select "section:nth-of-type(2) ##{dom_id(same_day)}"
    end
  end

  test "Load older: a day that goes on across the page boundary has its header at the foot of one page and the head of the next, once each" do
    travel_to Time.utc(2026, 10, 4, 18, 0) do
      51.times { |n| event(Time.utc(2026, 10, 4, 10, 0) - n.minutes) }

      get "/cs-studio/audit_events", params: { event_action: "test.screen" }
      assert_equal [ "Today" ], headers
      assert_select "a", text: "Load older"

      get "/cs-studio/audit_events", params: { event_action: "test.screen", offset: 50 }
      assert_equal [ "Today" ], headers
      assert_select "li[id^=audit_event_]", 1
      assert_select "a", text: "Newer"
    end
  end

  test "Load older: when the day changes at the boundary, the next page opens with the new day's header; filters are kept" do
    travel_to Time.utc(2026, 10, 4, 18, 0) do
      50.times { |n| event(Time.utc(2026, 10, 4, 10, 0) - n.minutes) }
      event(Time.utc(2026, 10, 3, 10, 0))

      get "/cs-studio/audit_events", params: { event_action: "test.screen", channel: "admin" }
      assert_equal [ "Today" ], headers
      assert_select "a[href*='offset=50'][href*='channel=admin'][href*='event_action=test.screen']", text: "Load older"

      get "/cs-studio/audit_events", params: { event_action: "test.screen", channel: "admin", offset: 50 }
      assert_equal [ "Yesterday" ], headers
      assert_select "a[href*='channel=admin'][href*='event_action=test.screen']", text: "Newer"
    end
  end

  # --- sentences -----------------------------------------------------------------

  test "rows read as sentences, with the raw key and the channel chip, security keys in warn ink" do
    post = as(@me) { create_post(title: "Hello world", published: false) }
    created = Audit::Event.find_by!(action: "post.created", subject: post)
    failed = event(Time.current, action: "session.failed", user_id: nil, ip: "203.0.113.4", metadata: { "email_address" => "who@example.com" })
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "claude-desktop")
    via = as(token, channel: :mcp) { create_post(title: "From MCP", published: false) }
    mcp = Audit::Event.find_by!(action: "post.created", subject: via)

    get "/cs-studio/audit_events"

    assert_select "##{dom_id(created)} p", text: "You created “Hello world”"
    assert_select "##{dom_id(created)} p a[href='/cs-studio/posts/#{post.id}']", text: "Hello world"
    assert_select "##{dom_id(created)} span.font-cs-mono", text: "post.created"
    assert_select "##{dom_id(created)} .admin-channel-chip", text: "ADMIN"
    assert_select "##{dom_id(failed)} p", text: "Failed sign-in attempt"
    assert_select "##{dom_id(failed)} span.text-warn-ink", text: "session.failed"
    assert_no_match(/who@example\.com/, response.body)
    assert_select "##{dom_id(mcp)} p", text: /#{Regexp.escape(users(:two).display_name)} via claude-desktop created “From MCP”/
    assert_select "##{dom_id(mcp)} .admin-channel-chip[data-channel=mcp]", text: "MCP"
    assert_select "##{dom_id(created)} span.text-warn-ink", count: 0
  end

  test "a stored block verb nothing knows renders as the generic sentence, list and event page" do
    odd = event(Time.current, action: "block.whatever", subject_type: "ContentBlock", subject_id: 999_999, subject_label: "Rich text block #999999")

    get "/cs-studio/audit_events"
    assert_response :success
    assert_select "##{dom_id(odd)} p", text: /did block\.whatever on “Rich text block #999999”/

    get "/cs-studio/audit_events/#{odd.id}"
    assert_response :success
  end

  test "the channel chip comes before the raw key at the right end of a row" do
    one = event(Time.current, action: "post.created")

    get "/cs-studio/audit_events"

    assert_operator response.body.index("data-channel=\"admin\"", response.body.index(dom_id(one))), :<, response.body.index(">post.created<", response.body.index(dom_id(one)))
  end

  # --- filters ---------------------------------------------------------------------

  test "the toolbar is one row of selects that apply on change" do
    get "/cs-studio/audit_events"

    assert_select "form[data-controller='admin--ui--auto-submit'][data-turbo-frame=content]" do
      %w[user_id event_action subject_type channel range].each { |name| assert_select "select##{name}" }
      assert_select "select#range option", text: "Today"
      assert_select "select#range option", text: "Last 7 days"
      assert_select "select#range option", text: "Last 30 days"
      assert_select "select#range option", text: "Last 90 days"
      assert_select "select#range option", text: "Custom…"
      assert_select "select#channel option", text: "MCP"
      assert_select "select#event_action optgroup[label=Posts] option", text: "post.published"
      assert_select "input#from", count: 0
    end
  end

  test "each filter narrows the list" do
    mine = event(1.hour.ago, action: "test.mine")
    theirs = event(1.hour.ago, action: "test.theirs", user_id: users(:two).id, channel: "mcp")
    page = event(1.hour.ago, action: "test.page", subject_type: "Page", subject_id: 1)

    get "/cs-studio/audit_events", params: { user_id: users(:two).id, event_action: "test.theirs" }
    assert_select "##{dom_id(theirs)}"
    assert_select "##{dom_id(mine)}", count: 0

    get "/cs-studio/audit_events", params: { channel: "mcp" }
    assert_select "##{dom_id(theirs)}"
    assert_select "##{dom_id(mine)}", count: 0
    assert_select "select#channel option[selected]", text: "MCP"

    get "/cs-studio/audit_events", params: { subject_type: "Page" }
    assert_select "##{dom_id(page)}"
    assert_select "##{dom_id(mine)}", count: 0
  end

  test "an action the catalogue doesn't know is offered under Other" do
    event(1.hour.ago, action: "acme/audit.exported")

    get "/cs-studio/audit_events"

    assert_select "select#event_action optgroup[label=Other] option", text: "acme/audit.exported"
  end

  test "date presets: Today, 7, 30 and 90 days, in the site zone" do
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      today = event(Time.utc(2026, 10, 4, 7, 0))
      three = event(Time.utc(2026, 10, 1, 7, 0))
      twenty = event(Time.utc(2026, 9, 14, 7, 0))
      sixty = event(Time.utc(2026, 8, 5, 7, 0))
      old = event(Time.utc(2026, 1, 5, 7, 0))
      shown = ->(range) { get "/cs-studio/audit_events", params: { range:, event_action: "test.screen" }; css_select("li[id^=audit_event_]").map { |node| node["id"] } }

      assert_equal [ dom_id(today) ], shown.("today")
      assert_equal [ dom_id(today), dom_id(three) ], shown.("7")
      assert_equal [ dom_id(today), dom_id(three), dom_id(twenty) ], shown.("30")
      assert_equal [ dom_id(today), dom_id(three), dom_id(twenty), dom_id(sixty) ], shown.("90")
      assert_not_includes shown.(""), nil
      assert_includes shown.(""), dom_id(old)
      assert_select "select#range option[selected]", text: "Any time", count: 0 # "" is the blank option, nothing else
    end
  end

  test "Custom shows From and To inline, filters inclusively, and a reversed range is swapped" do
    inside = event(Time.utc(2026, 6, 15, 12))
    outside = event(Time.utc(2026, 7, 15, 12))

    get "/cs-studio/audit_events", params: { range: "custom", from: "2026-06-01", to: "2026-06-30", event_action: "test.screen" }
    assert_select "select#range option[selected]", text: "Custom…"
    assert_select "input#from[type=date][value='2026-06-01']"
    assert_select "input#to[type=date][value='2026-06-30']"
    assert_select "##{dom_id(inside)}"
    assert_select "##{dom_id(outside)}", count: 0

    get "/cs-studio/audit_events", params: { range: "custom", from: "2026-06-30", to: "2026-06-01", event_action: "test.screen" }
    assert_response :success
    assert_select "##{dom_id(inside)}"
    assert_select "input#from[value='2026-06-01']"

    get "/cs-studio/audit_events", params: { range: "custom", event_action: "test.screen" } # no dates yet: no restriction
    assert_select "##{dom_id(outside)}"
  end

  test "junk filter values are all, never a 500" do
    get "/cs-studio/audit_events", params: { user_id: "x", range: "99", channel: "fax", from: "no", to: "no", subject_type: "Post", subject_id: "abc", event_action: "a" * 500 }
    assert_response :success
  end

  test "a subject filter shows a removable chip and keeps its values" do
    post = as(@me) { create_post(title: "Chip post", published: false) }

    get "/cs-studio/audit_events", params: { subject_type: "Post", subject_id: post.id, channel: "admin" }

    assert_select "[data-subject-chip]", text: /About this post ##{post.id}/
    assert_select "input[type=hidden][name=subject_type][value=Post]"
    assert_select "input[type=hidden][name=subject_id][value='#{post.id}']"
    assert_select "select#subject_type", count: 0
    assert_select "[data-subject-chip] a[href*='channel=admin']" do |links|
      assert_no_match(/subject_/, links.first["href"])
    end
  end

  test "an empty result with filters names them; Clear filters resets" do
    get "/cs-studio/audit_events", params: { event_action: "nothing.like.this" }

    assert_select "p, h2, h3", text: /No matches/
    assert_select "a", text: "Clear filters"
  end

  # --- the event page --------------------------------------------------------------

  test "the event page: sentence title, when with saves, who, channel, action, object, request, IP" do
    post = as(@me) { create_post(title: "Welcome", published: false) }
    spanned = event(Time.utc(2026, 10, 2, 14, 5), last: Time.utc(2026, 10, 2, 14, 31), occurrences: 12, action: "post.updated",
      subject_type: "Post", subject_id: post.id, subject_label: "Welcome", request_id: "7c1e-req", ip: "203.0.113.9")

    get "/cs-studio/audit_events/#{spanned.id}"

    assert_select "h1", text: "You edited “Welcome”"
    assert_select "h1 a[href='/cs-studio/posts/#{post.id}']"
    assert_select "dl", text: /Fri 2 Oct 2026, 16:05–16:31 · 12 saves/
    assert_select "dd", text: "post.updated"
    assert_select "dd", text: "Post ##{post.id} · Welcome"
    assert_select "dd", text: "7c1e-req"
    assert_select "dd", text: "203.0.113.9"
    assert_select "dl .admin-channel-chip", text: "ADMIN"
  end

  test "a title change in two languages is grouped per language with word diffs" do
    with_locales(%w[en de], default: "en") do
      post = as(@me) { create_post(title: "Welcome to the new site", published: false) }
      as(@me) do
        Posts::Save.call(post, translations: { "en" => { title: "Welcome to our new site" }, "de" => { title: "Willkommen", excerpt: "Neu gebaut" } })
      end
      updated = Audit::Event.where(action: "post.updated", subject: post).sole

      get "/cs-studio/audit_events/#{updated.id}"

      assert_response :success
      assert_select "[data-changes-group=en] p", text: "1 FIELD · ENGLISH"
      assert_select "[data-changes-group=de] p", text: "2 FIELDS · DEUTSCH"
      assert_select "[data-changes-group=en] tr", text: /title/ do
        assert_select "del", text: /the/
        assert_select "ins", text: /our/
        assert_select "del .sr-only", text: "Removed:"
        assert_select "ins .sr-only", text: "Added:"
      end
      assert_select "[data-changes-group=de] tr", text: /excerpt/ do
        assert_select "td", text: /Empty/
        assert_select "ins", text: /Neu gebaut/
      end
    end
  end

  test "a language since turned off is labelled by its code" do
    changes = event(Time.current, action: "post.updated", field_changes: { "fr title" => [ "a", "b" ] })

    get "/cs-studio/audit_events/#{changes.id}"

    assert_select "p", text: "1 FIELD · FR"
  end

  test "digest-only, flag and list changes read plainly; bookkeeping and secrets are never shown" do
    changes = event(Time.current, action: "post.updated", field_changes: {
      "en body" => { "digest_before" => "abcdef0123", "digest_after" => "fedcba3210" },
      "published" => [ false, true ], "tag_ids" => [ [ 1 ], [ 1, 2 ] ],
      "translation_sources" => { "title" => { "de" => "x" } }, "password_digest" => [ "old-secret-digest", "new-secret-digest" ]
    })

    get "/cs-studio/audit_events/#{changes.id}"

    assert_select "tr", text: /body.*Changed/m
    assert_select "tr", text: /published.*false.*true/m
    assert_select "tr", text: /tag_ids.*\[1\].*\[1,2\]/m
    assert_no_match(/abcdef0123|fedcba3210/, response.body)
    assert_no_match(/translation_sources|secret-digest/, response.body.sub(/<pre.*?<\/pre>/m, ""))
  end

  test "text too long to compare word by word says so and shows both sides, cut" do
    long = event(Time.current, action: "post.updated", field_changes: { "en excerpt" => [ "alpha " * 5_000, "beta " * 5_000 ] })

    get "/cs-studio/audit_events/#{long.id}"

    assert_response :success
    assert_select "td", text: /The text is too long to compare word by word\./
    assert_select "del", count: 0
    assert_operator response.body.scan("alpha").size, :<, 400 # cut at 2,000 characters, not 30,000
  end

  test "stored values are escaped text" do
    changes = event(Time.current, action: "post.updated", field_changes: { "en title" => [ "<img src=x onerror=alert(1)>", "<script>alert(2)</script>" ], "flag" => [ "<b>x</b>", nil ] })

    get "/cs-studio/audit_events/#{changes.id}"

    assert_no_match(/<img src=x|<script>alert\(2\)|<b>x<\/b>/, response.body.sub(/<pre.*?<\/pre>/m, ""))
    assert_includes response.body, "&lt;img src=x onerror=alert(1)&gt;"
  end

  test "ai.translated has no snapshot and no changes, and still shows" do
    translated = event(Time.current, action: "ai.translated", snapshot: nil, metadata: { "provider" => "anthropic" })

    get "/cs-studio/audit_events/#{translated.id}"

    assert_response :success
    assert_select "p", text: "No field changes recorded."
    assert_select "details", count: 0
  end

  test "Older and Newer follow the list's order, keep the filters, and stop at the ends" do
    first = event(Time.utc(2026, 10, 1, 8))
    middle = event(Time.utc(2026, 10, 2, 8))
    last = event(Time.utc(2026, 10, 3, 8))
    other = event(Time.utc(2026, 10, 2, 9), action: "test.other") # not in the filter below

    get "/cs-studio/audit_events/#{middle.id}", params: { event_action: "test.screen" }
    assert_select "a[href*='/audit_events/#{first.id}'][href*='event_action=test.screen']", text: /Older event/
    assert_select "a[href*='/audit_events/#{last.id}'][href*='event_action=test.screen']", text: /Newer event/

    get "/cs-studio/audit_events/#{last.id}", params: { event_action: "test.screen" }
    assert_select "a", text: /Newer event/, count: 0
    get "/cs-studio/audit_events/#{first.id}", params: { event_action: "test.screen" }
    assert_select "a", text: /Older event/, count: 0

    get "/cs-studio/audit_events/#{middle.id}" # unfiltered: the other event is between
    assert_select "a[href*='/audit_events/#{other.id}']", text: /Newer event/
  end

  test "the list's rows link to the event with the filters, and the breadcrumb goes back with them" do
    one = event(Time.current)

    get "/cs-studio/audit_events", params: { event_action: "test.screen", channel: "admin" }
    assert_select "##{dom_id(one)} a[href*='/audit_events/#{one.id}'][href*='channel=admin'][href*='event_action=test.screen']"

    get "/cs-studio/audit_events/#{one.id}", params: { event_action: "test.screen", channel: "admin" }
    assert_select "a[href*='/audit_events?'][href*='channel=admin']", text: "Audit log"
  end

  # Final fix wave (I3): an event's link used to die with its filter -- a URL
  # carrying `range=today` was a 404 the next morning, and a link pasted with
  # a filter the event doesn't match was "not found" for an event that exists.
  # The event is found whatever the filter says; outside it, the answer is
  # the event's own filter-free address (where Older/Newer walk the whole log).
  test "an event outside the filters redirects to its filter-free permalink; only a missing id is a 404" do
    older = event(2.minutes.ago)
    one = event(1.minute.ago)
    newer = event(Time.current)

    get "/cs-studio/audit_events/#{one.id}", params: { channel: "mcp" }
    assert_redirected_to "/cs-studio/audit_events/#{one.id}"
    follow_redirect!
    assert_response :success
    # The permalink carries no filter, and neither does any link on it.
    assert_select "a[href='/cs-studio/audit_events']", text: "Audit log"
    assert_select "a[href='/cs-studio/audit_events/#{older.id}']", text: /Older event/
    assert_select "a[href='/cs-studio/audit_events/#{newer.id}']", text: /Newer event/
    assert_select "a[href*='channel=']", count: 0

    travel_to 2.days.from_now do
      get "/cs-studio/audit_events/#{one.id}", params: { range: "today", locale: "de" }
      assert_redirected_to "/cs-studio/audit_events/#{one.id}?locale=de"
    end

    # Inside its filters it renders where it was asked for, and every link on
    # the page keeps them: back to the list, Older and Newer.
    get "/cs-studio/audit_events/#{one.id}", params: { channel: "admin", event_action: "test.screen" }
    assert_response :success
    assert_select "a[href^='/cs-studio/audit_events?'][href*='channel=admin'][href*='event_action=test.screen']", text: "Audit log"
    assert_select "a[href^='/cs-studio/audit_events/#{older.id}?'][href*='channel=admin'][href*='event_action=test.screen']", text: /Older event/
    assert_select "a[href^='/cs-studio/audit_events/#{newer.id}?'][href*='channel=admin'][href*='event_action=test.screen']", text: /Newer event/

    get "/cs-studio/audit_events/0", params: { channel: "mcp" }
    assert_response :not_found
    assert_select "nav[aria-label='Modules']"
    get "/cs-studio/audit_events/0"
    assert_response :not_found
  end

  # Final fix wave (M5b): `offset` is the visitor's to type.
  test "an absurd offset is clamped, never a database error" do
    event(Time.current)

    get "/cs-studio/audit_events", params: { offset: "9" * 40 }
    assert_response :success
    assert_select "section[aria-labelledby^=audit-day]", count: 0

    get "/cs-studio/audit_events", params: { offset: "-5" }
    assert_response :success
    assert_select "section[aria-labelledby^=audit-day]", minimum: 1
  end

  # Final fix wave (M12): a filter on a user who has since been deleted (the
  # link from one of their events) showed "Anyone" in the drop-down while the
  # list was filtered.
  test "a user filter naming a deleted user is shown as chosen" do
    gone = User.maximum(:id) + 500
    event(Time.current, user_id: gone)

    get "/cs-studio/audit_events", params: { user_id: gone }

    assert_select "select#user_id option[selected][value='#{gone}']", text: "A deleted user"
  end

  # Final fix wave (M2): a refusal said what was refused but not on what,
  # though the event page's Object line already names it.
  test "a refusal names what it was refused on, linked for a viewer who can open it" do
    post = as(@me) { create_post(title: "Guarded post", published: false) }
    denied = event(Time.current, action: "access.denied", user_id: users(:author).id, subject_type: "Post", subject_id: post.id,
      subject_label: "Guarded post", metadata: { "permission" => "posts.edit" })
    bare = event(Time.current, action: "access.denied", user_id: users(:author).id, subject_label: nil, metadata: { "permission" => "settings.manage" })

    get "/cs-studio/audit_events"

    assert_select "##{dom_id(denied)} p", text: "#{users(:author).display_name} was refused permission to edit posts on “Guarded post”"
    assert_select "##{dom_id(denied)} p a[href='/cs-studio/posts/#{post.id}']", text: "Guarded post"
    assert_select "##{dom_id(bare)} p", text: "#{users(:author).display_name} was refused permission to manage settings"
  end

  # Final fix wave (M10): an image's event links to its panel only for a
  # viewer who can open the library, and never for a trashed image.
  test "an image's row links to its panel for a media.upload holder, and is plain text without it or once the image is trashed" do
    asset = as(@me) { create_media_asset }
    row = event(Time.current, action: "media.updated", subject_type: "Media::Asset", subject_id: asset.id, subject_label: "Sunset")

    get "/cs-studio/audit_events"
    assert_select "##{dom_id(row)} p a[href='/cs-studio/media?selected=#{asset.id}']", text: "Sunset"

    group = AccessControl::Group.create!(name: "Audit only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "audit.view")
    viewer = User.create!(email_address: "audit-only-m@example.com", password: "password12345")
    AccessControl::Membership.create!(user: viewer, group:)
    sign_in_as(viewer)
    get "/cs-studio/audit_events"
    assert_select "##{dom_id(row)} p", text: /edited “Sunset”/
    assert_select "##{dom_id(row)} p a", count: 0

    as(@me) { assert Trash::Move.call(asset).ok? }
    sign_in_as(@me)
    get "/cs-studio/audit_events"
    assert_select "##{dom_id(row)} p", text: /edited “Sunset”/
    assert_select "##{dom_id(row)} p a", count: 0
  end

  # Final fix wave: the list and the event page must render whatever a row
  # holds -- no subject at all, and JSON columns that aren't the hashes the
  # components expect (a hand-written or a legacy row).
  test "a row with no subject type, a list for its field changes and a list for its metadata renders in the list and on its own page" do
    junk = event(Time.current, action: "page.updated", subject_type: nil, subject_id: nil, subject_label: nil, field_changes: [ 1 ], metadata: [], snapshot: nil)
    odd = event(Time.current, action: "access.denied", subject_type: nil, subject_label: "", field_changes: [ 1 ], metadata: [])

    get "/cs-studio/audit_events"
    assert_response :success
    assert_select "##{dom_id(junk)} p", text: /You edited/
    assert_select "##{dom_id(odd)} p", text: "You were refused access"

    [ junk, odd ].each do |row|
      get "/cs-studio/audit_events/#{row.id}"
      assert_response :success
      assert_select "h1"
    end
  end

  test "a coalesced event that is not an edit counts times, not saves" do
    refused = event(Time.utc(2026, 10, 2, 14, 5), last: Time.utc(2026, 10, 2, 14, 9), occurrences: 12, action: "access.denied", metadata: { "permission" => "posts.edit" })

    get "/cs-studio/audit_events/#{refused.id}"

    assert_select "dl", text: /Fri 2 Oct 2026, 16:05–16:09 · 12 times/
    assert_select "dl", text: /saves/, count: 0
  end

  test "an event page for a record the viewer can't read links nothing but still names it" do
    post = as(@me) { create_post(title: "Hidden title", published: false) }
    created = Audit::Event.find_by!(action: "post.created", subject: post)
    group = AccessControl::Group.create!(name: "Audit only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "audit.view")
    viewer = User.create!(email_address: "audit-only-s@example.com", password: "password12345")
    AccessControl::Membership.create!(user: viewer, group:)
    sign_in_as(viewer)

    get "/cs-studio/audit_events/#{created.id}"

    assert_select "h1 a", count: 0
    assert_select "h1", text: /Hidden title/
    assert_select "h1", text: /#{Regexp.escape(@me.display_name)} created/
  end

  # --- cost --------------------------------------------------------------------------

  test "the list costs the same queries for 2 events as for 20, of mixed kinds" do
    day = ->(n) { Time.utc(2026, 2, n) }
    seed = lambda do |count, at|
      count.times do |i|
        travel_to(at) do
          post = as(@me) { create_post(title: "M#{count}-#{i}", published: false) }
          page = as(@me) { create_page(title: "MP#{count}-#{i}", published: false) }
          as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")) }
          token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "T#{count}-#{i}")
          as(token, channel: :mcp) { Posts::Save.call(post, translations: { "en" => { title: "Edited #{count}-#{i}" } }) }
          Audit.record("session.created", subject: users(:two))
          Audit.record("session.failed", metadata: { "email_address" => "x@y.z" })
          Audit.record("access.denied", subject: post, metadata: { "permission" => "posts.delete" })
          Audit.record("acme/audit.exported")
        end
      end
    end
    seed.(2, day.(1))
    seed.(20, day.(10))

    get "/cs-studio/audit_events", params: { range: "custom", from: "1999-01-01", to: "1999-01-02" } # warm-up, uncounted
    counted = lambda do |from, to|
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/cs-studio/audit_events", params: { range: "custom", from:, to: }
      end
      assert_response :success
      queries
    end
    few = ActiveRecord::Base.uncached { counted.("2026-02-01", "2026-02-02") }
    many = ActiveRecord::Base.uncached { counted.("2026-02-10", "2026-02-10") }

    assert_operator css_select("li[id^=audit_event_]").size, :>=, 20
    assert_equal few, many
  end
end
