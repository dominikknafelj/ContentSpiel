require "test_helper"

# `Audit::Sentence` words one audit event as plain data (design pass round 3,
# Task 15): the log, the event page and the dashboard all use it.
class Audit::SentenceTest < ActiveSupport::TestCase
  setup { @me = users(:one) }

  # "You published “Hello”" -- the sentence as a person would read it.
  def read(sentence)
    actor = sentence.actor
    name = if actor.none then nil
    elsif actor.you then "You"
    else (actor.user&.display_name || (actor.user_id ? "a deleted user" : "System"))
    end
    via = actor.via_label ? (actor.you ? ", via #{actor.via_label}" : " via #{actor.via_label}") : ""
    words = sentence.parts.map { |part| part.kind == :subject ? "“#{part.text}”" : part.text }.join
    [ ("#{name}#{via}" if name), words ].compact.join(" ")
  end

  def sentence_for(event, viewer: @me) = Audit::Sentence.for(event, viewer:, channel: :admin)

  def event(action, **attributes)
    Audit::Event.create!({ action:, channel: "admin", user_id: @me.id, occurred_at: Time.current, last_occurred_at: Time.current }.merge(attributes))
  end

  # --- every recorded action has a sentence ---------------------------------

  # The call sites whose action isn't one literal: a `record_event(` /
  # `Audit.record(` whose first argument is a variable or an interpolation.
  # Each is listed here with what it can produce, and the test fails for a NEW
  # such site not listed (and for any action, literal or listed, without a
  # sentence). A literal anywhere on a call line -- `record_event(created ?
  # "block.created" : "block.updated", ...)` -- is found by the scan itself.
  DYNAMIC_SITES = {
    # `ApplicationService#record_event` and `#denied` pass what they are given on.
    "app/services/application_service.rb" => [],
    # `publish_action`
    "app/services/posts/save.rb" => %w[post.unpublished post.scheduled post.published],
    # `action` = Pages::Save#publish_action
    "app/services/pages/save.rb" => %w[page.unpublished page.published],
    # "#{event_prefix}.trashed" / ".restored" / ".purged": page, post or media
    "app/services/trash/move.rb" => %w[page.trashed post.trashed media.trashed],
    "app/services/trash/restore.rb" => %w[page.restored post.restored media.restored],
    "app/services/trash/purge.rb" => %w[page.purged post.purged media.purged],
    # "#{EVENT.fetch(record class)}.translation_confirmed": page post block media settings
    "app/services/translations/confirm.rb" => %w[page.translation_confirmed post.translation_confirmed block.translation_confirmed
      media.translation_confirmed settings.translation_confirmed],
    # "#{PREFIX.fetch(subject class)}.taken_over": a block, a page's settings or a post
    # "#{prefix}.changes_published": a page or a post
    "app/services/publishing/publish_changes.rb" => %w[page.changes_published post.changes_published],
    "app/services/editing/take_over.rb" => %w[page.taken_over post.taken_over block.taken_over]
  }.freeze

  def scan_recorded_actions
    literals = []
    unlisted = []
    Dir[Rails.root.join("app/**/*.rb")].each do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      File.readlines(path).each_with_index do |line, index|
        next if line.strip.start_with?("#") || line.match?(/\bdef record_event\b/)

        call = line[/(?:record_event|Audit\.record)\(\s*([^,)]*)/, 1]
        next unless call

        found = line.scan(/"([a-z_]+\.[a-z_]+)"/).flatten
        literals.concat(found)
        # Literal-led call: fine. Anything else (a variable, an interpolation)
        # must be a listed dynamic site.
        plain_literal = call.match?(/\A"[a-z_]+\.[a-z_]+"\z/)
        ternary_of_literals = found.any? && call.include?("?")
        unlisted << "#{relative}:#{index + 1}: #{line.strip}" unless plain_literal || ternary_of_literals || DYNAMIC_SITES.key?(relative)
      end
    end
    [ literals.uniq, unlisted ]
  end

  test "every action recorded anywhere in app/ has a sentence" do
    literals, unlisted = scan_recorded_actions

    assert_empty unlisted, "a record_event/Audit.record whose action isn't a literal: add its site to DYNAMIC_SITES with what it can produce"
    recorded = (literals + DYNAMIC_SITES.values.flatten).uniq
    assert_operator recorded.size, :>=, 50 # the scan itself must not have gone blind
    assert_empty recorded - Audit::Sentence::ACTIONS, "actions with no sentence in Audit::Sentence"
  end

  test "the sentence table lists no action nothing records" do
    literals, = scan_recorded_actions
    recorded = literals + DYNAMIC_SITES.values.flatten
    # `session.destroyed`, `block.*`, ... are all recorded somewhere; a retired
    # action's sentence should go with it.
    assert_empty Audit::Sentence::ACTIONS - recorded, "sentences for actions nothing records any more"
  end

  test "every known action reads as a sentence, never the plugin fallback" do
    Audit::Sentence::ACTIONS.each do |action|
      sentence = sentence_for(Audit::Event.new(action:, channel: "admin", user_id: @me.id, subject_label: "Thing",
        subject_type: "Page", subject_id: 1, occurred_at: Time.current, last_occurred_at: Time.current))
      assert_no_match(/\bdid #{Regexp.escape(action)}\b/, read(sentence), action)
    end
  end

  # --- wording ---------------------------------------------------------------

  test "one sentence per action family, with You for the viewer" do
    post = as(@me) { create_post(title: "Hello", published: false) }
    as(@me) { Posts::Save.call(post, attributes: { published: true }) }
    created = Audit::Event.find_by!(action: "post.created", subject: post)
    published = Audit::Event.find_by!(action: "post.published", subject: post)

    assert_equal "You created “Hello”", read(sentence_for(created))
    assert_equal "You published “Hello”", read(sentence_for(published))
    assert_equal "#{@me.display_name} published “Hello”", read(sentence_for(published, viewer: users(:two)))
    assert_equal "You moved “Hello” to the trash", read(sentence_for(event("post.trashed", subject_type: "Post", subject_id: post.id, subject_label: "Hello")))
  end

  test "the other families" do
    cases = {
      %w[tag.renamed Tag] => "renamed the tag “news”",
      %w[tag.deleted Tag] => "deleted the tag “news”",
      %w[tag.merged Tag] => "merged another tag into the tag “news”",
      %w[user.created User] => "added the user “news”",
      %w[group.deleted AccessControl::Group] => "deleted the group “news”",
      %w[token.issued ApiToken] => "created the API token “news”",
      %w[token.revoked ApiToken] => "revoked the API token “news”",
      %w[settings.updated SiteSetting] => "edited “news”",
      %w[media.uploaded Media::Asset] => "uploaded “news”",
      %w[page.purged Page] => "permanently deleted “news”",
      %w[ai.translated Post] => "asked the AI for translation suggestions for “news”"
    }
    cases.each do |(action, type), expected|
      read = read(sentence_for(Audit::Event.new(action:, channel: "admin", subject_type: type, subject_id: 999_999, subject_label: "news",
        user_id: @me.id, occurred_at: Time.current, last_occurred_at: Time.current)))
      assert_equal "You #{expected}", read, action
    end
  end

  test "sentences with no subject" do
    base = { channel: "admin", user_id: @me.id, occurred_at: Time.current, last_occurred_at: Time.current }
    assert_equal "You signed in", read(sentence_for(Audit::Event.new(base.merge(action: "session.created"))))
    assert_equal "You signed out", read(sentence_for(Audit::Event.new(base.merge(action: "session.destroyed"))))
    assert_equal "You emptied the trash", read(sentence_for(Audit::Event.new(base.merge(action: "trash.emptied"))))
    assert_equal "You added the starter content", read(sentence_for(Audit::Event.new(base.merge(action: "starter_content.added"))))
    assert_equal "You turned on German", read(sentence_for(Audit::Event.new(base.merge(action: "language.enabled", metadata: { "code" => "de" }))))
    assert_equal "You turned off German", read(sentence_for(Audit::Event.new(base.merge(action: "language.disabled", metadata: { "code" => "de" }))))
    assert_equal "You made German the default language", read(sentence_for(Audit::Event.new(base.merge(action: "language.default_changed", metadata: { "code" => "de" }))))
    assert_equal "You changed the languages", read(sentence_for(Audit::Event.new(base.merge(action: "language.configured"))))
  end

  test "a failed sign-in has no actor and never echoes the attempted address" do
    failed = event("session.failed", channel: "admin", metadata: { "email_address" => "someone@example.com" }, ip: "203.0.113.4")
    sentence = sentence_for(failed)

    assert sentence.actor.none
    assert sentence.security
    assert_equal "Failed sign-in attempt", read(sentence)
    assert_no_match(/someone@example\.com/, read(sentence))
  end

  test "a refused permission reads as the permission's own label, security flagged" do
    denied = event("access.denied", user_id: users(:author).id, metadata: { "permission" => "settings.manage" })
    sentence = sentence_for(denied)

    assert_equal "#{users(:author).display_name} was refused permission to manage settings", read(sentence)
    assert sentence.security
    assert_equal "You were refused access", read(sentence_for(event("access.denied", metadata: {})))
  end

  test "owner changes read from the new value" do
    on = event("user.owner_changed", subject_type: "User", subject_id: users(:two).id, subject_label: "two", field_changes: { "owner" => [ false, true ] })
    off = event("user.owner_changed", subject_type: "User", subject_id: users(:two).id, subject_label: "two", field_changes: { "owner" => [ true, false ] })

    assert_equal "You made “two” an owner", read(sentence_for(on))
    assert_equal "You removed owner rights from “two”", read(sentence_for(off))
    assert sentence_for(on).security
  end

  test "the security keys" do
    secure = %w[session.failed access.denied user.owner_changed token.issued token.revoked user.deleted group.deleted]
    assert_equal secure.sort, Audit::Sentence::ACTIONS.select { |action| sentence_for(Audit::Event.new(action:, occurred_at: Time.current, last_occurred_at: Time.current)).security }.sort
  end

  test "a block event is about the page that owns it, with the block's type" do
    page = as(@me) { create_page(title: "Blog") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "post_list")).record }
    created = Audit::Event.find_by!(action: "block.created", subject: block)

    sentence = sentence_for(created)
    assert_equal "You added a Post list block to “Blog”", read(sentence)
    assert_equal :admin_page_path, sentence.subject_route.name
    assert_equal [ page.id ], sentence.subject_route.args

    as(@me) { ContentBlocks::Destroy.call(block) }
    assert_equal "You deleted a Post list block from “Blog”", read(sentence_for(Audit::Event.find_by!(action: "block.deleted", subject_type: "ContentBlock", subject_id: block.id)))
  end

  test "a block on a page the viewer can't read names only the block, with no link" do
    page = as(@me) { create_page(title: "Secret page") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
    created = Audit::Event.find_by!(action: "block.created", subject: block)

    sentence = sentence_for(created, viewer: audit_only_viewer)

    assert_nil sentence.subject_route
    assert_equal "added “Rich text block ##{block.id}”", read(sentence).sub(/\A\S+@\S+ /, "")
    assert_no_match(/Secret page/, read(sentence))
  end

  test "a page's own alt-only media edit and a scheduling read as what they are" do
    asset = create_media_asset
    alt = event("media.updated", subject_type: "Media::Asset", subject_id: asset.id, subject_label: "tiny", field_changes: { "en alt" => [ "a", "b" ] })
    assert_equal "You updated the alt text of “tiny”", read(sentence_for(alt))

    post = as(@me) { create_post(title: "Later", published: false) }
    scheduled = event("post.updated", subject_type: "Post", subject_id: post.id, subject_label: "Later",
      field_changes: { "published_at" => [ nil, 2.days.from_now.iso8601 ] })
    assert_match(/\AYou scheduled “Later” for \d{1,2} \w{3}\z/, read(sentence_for(scheduled)))
  end

  test "a plugin's action falls back to did <action> on <subject>" do
    plugin = event("acme/audit.exported", subject_type: "Post", subject_id: 1, subject_label: "Report", user_id: @me.id)

    assert_equal "You did acme/audit.exported on “Report”", read(sentence_for(plugin))
    assert_equal "You did acme/audit.exported", read(sentence_for(event("acme/audit.exported", user_id: @me.id)))
  end


  # --- derived verbs, through the real service paths -----------------------------

  def latest_event(record) = Audit::Event.where(subject: record).order(:id).last

  def each_kind
    { "page" => ->(title) { as(@me) { create_page(title:, published: false) } }, "post" => ->(title) { as(@me) { create_post(title:, published: false) } } }
  end

  def save_at(record, at)
    as(@me) { (record.is_a?(Page) ? Pages::Save : Posts::Save).call(record, attributes: { published_at: at }) }
    latest_event(record.reload)
  end

  test "scheduling, rescheduling, removing a schedule, publishing now and unpublishing read right for pages and posts" do
    each_kind.each do |kind, make|
      record = make.call("Sched #{kind}")
      later = 3.days.from_now.change(usec: 0)

      assert_match(/\AYou scheduled “Sched #{kind}” for \d{1,2} \w{3}\z/, read(sentence_for(save_at(record, later))), "schedule #{kind}")
      assert_match(/\AYou scheduled “Sched #{kind}” for /, read(sentence_for(save_at(record, later + 2.days))), "reschedule #{kind}")
      # Taking a FUTURE date away never took anything off the site: it removes a schedule.
      assert_equal "You removed the schedule from “Sched #{kind}”", read(sentence_for(save_at(record, nil))), "remove schedule #{kind}"
      save_at(record, later)
      assert_equal "You published “Sched #{kind}”", read(sentence_for(save_at(record, Time.current - 1.minute))), "publish now #{kind}"
      assert_equal "You unpublished “Sched #{kind}”", read(sentence_for(save_at(record, nil))), "unpublish #{kind}"
      assert_no_match(/\bdid\b/, read(sentence_for(latest_event(record))))
    end
  end

  # A date in the past is a publication, however far back: backdating a draft
  # publishes it, moving a live record's date leaves it published, and taking
  # a past date away unpublishes it (never "removed the schedule").
  test "backdating reads as publishing, and removing a past date as unpublishing" do
    each_kind.each do |kind, make|
      record = make.call("Back #{kind}")

      assert_equal "You published “Back #{kind}”", read(sentence_for(save_at(record, 2.years.ago.change(usec: 0)))), "backdate #{kind}"
      assert_no_match(/schedule/, read(sentence_for(save_at(record, 3.years.ago.change(usec: 0)))), "move the date further back #{kind}")
      assert_equal "You unpublished “Back #{kind}”", read(sentence_for(save_at(record, nil))), "unpublish #{kind}"
    end
  end

  test "an unpublished event with junk for its changes still reads as unpublished" do
    [ [ 1 ], {}, { "published_at" => "not a time" }, { "published_at" => [ "junk", nil ] }, { "published_at" => [ nil, nil ] } ].each do |changes|
      row = event("post.unpublished", subject_label: "Thing", field_changes: changes)
      assert_equal "You unpublished “Thing”", read(sentence_for(row)), changes.inspect
    end
  end

  test "a refusal names its subject when the event has one" do
    denied = event("access.denied", user_id: users(:author).id, subject_label: "Guarded", metadata: { "permission" => "posts.edit" })

    assert_equal "#{users(:author).display_name} was refused permission to edit posts on “Guarded”", read(sentence_for(denied))
    assert_equal "You were refused access on “Guarded”", read(sentence_for(event("access.denied", subject_label: "Guarded", metadata: {})))
  end

  test "a block verb nothing knows reads as the generic sentence, with or without a readable owner" do
    page = as(@me) { create_page(title: "Blog") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
    odd = event("block.whatever", subject_type: "ContentBlock", subject_id: block.id, subject_label: "Rich text block ##{block.id}")

    assert_equal "You did block.whatever on “Blog”", read(sentence_for(odd))
    assert_equal "did block.whatever on “Rich text block ##{block.id}”", read(sentence_for(odd, viewer: audit_only_viewer)).sub(/\A\S+ /, "")
  end

  test "junk in stored data never raises" do
    junk = [
      { field_changes: nil, metadata: nil, snapshot: "x" }, { field_changes: [ 1 ], metadata: [ 2 ], snapshot: [ 3 ] },
      { field_changes: { "published_at" => { "a" => 1 }, "owner" => "x" }, metadata: { "code" => 5, "permission" => {} }, snapshot: { "block_type" => 7, "owner_type" => "Nope", "owner_id" => "z" } }
    ]
    junk.each do |attributes|
      (Audit::Sentence::ACTIONS + %w[block.x nope.nope]).each do |action|
        %w[ContentBlock Page Nope].each do |type|
          assert_nothing_raised { Audit::Sentence.for_events([ Audit::Event.new({ action:, subject_type: type, subject_id: 1, subject_label: "L", occurred_at: Time.current, last_occurred_at: Time.current }.merge(attributes)) ], viewer: @me, channel: :admin) }
        end
      end
    end
  end

  # --- who ---------------------------------------------------------------------

  test "the viewer's own token reads You via its name; another's reads their name via it" do
    token, = ApiToken.generate!(@me, group: access_control_groups(:admin), name: "Claude desktop")
    through = as(token, channel: :mcp) { create_post(title: "Via MCP", published: false) }
    created = Audit::Event.find_by!(action: "post.created", subject: through)

    assert_equal "You, via Claude desktop created “Via MCP”", read(sentence_for(created))
    assert_equal "#{@me.display_name} via Claude desktop created “Via MCP”", read(sentence_for(created, viewer: users(:two)))
    ApiToken.delete_all
    assert_equal "Claude desktop", sentence_for(created.reload).actor.via_label
  end

  test "no user reads System; a user who is gone reads a deleted user; a token whose user is gone too" do
    assert_equal "System", read(sentence_for(event("post.created", subject_label: "x", user_id: nil))).split(" ").first
    assert_match(/\Aa deleted user /, read(sentence_for(event("post.created", subject_label: "x", user_id: 999_999))))
    orphan = event("post.created", subject_label: "x", channel: "mcp", actor_type: "ApiToken", actor_id: 5, actor_label: "Claude", user_id: nil)
    assert_match(/\Aa deleted user via Claude /, read(sentence_for(orphan)))
  end

  # --- the subject: linked only when the viewer may open it ----------------------

  def audit_only_viewer
    group = AccessControl::Group.create!(name: "Audit only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "audit.view")
    User.create!(email_address: "audit-only-#{SecureRandom.hex(3)}@example.com", password: "password12345").tap do |user|
      AccessControl::Membership.create!(user:, group:)
    end
  end

  test "a subject links when the viewer can read it, and is its stored label otherwise" do
    post = as(@me) { create_post(title: "Gated", published: false) }
    created = Audit::Event.find_by!(action: "post.created", subject: post)

    linked = sentence_for(created)
    assert_equal :admin_post_path, linked.subject_route.name
    assert_equal "Gated", linked.subject_label

    plain = sentence_for(created, viewer: audit_only_viewer)
    assert_nil plain.subject_route
    assert_equal "Gated", plain.subject_label
  end

  test "a trashed or deleted subject is its stored label without a link, never a lookup that raises" do
    post = as(@me) { create_post(title: "Going", published: false) }
    created = Audit::Event.find_by!(action: "post.created", subject: post)
    as(@me) { Trash::Move.call(post) }
    assert_nil sentence_for(created).subject_route
    assert_equal "Going", sentence_for(created).subject_label

    as(@me) { Trash::Purge.call(post.reload) }
    assert_nil sentence_for(created).subject_route
    assert_equal "Going", sentence_for(created).subject_label
  end

  test "users, groups, settings and images link to the right place, by the right to manage them" do
    asset = create_media_asset
    group = access_control_groups(:admin)
    events = [
      event("user.updated", subject_type: "User", subject_id: users(:two).id, subject_label: "two"),
      event("group.updated", subject_type: "AccessControl::Group", subject_id: group.id, subject_label: "Admin"),
      event("settings.updated", subject_type: "SiteSetting", subject_id: site_settings(:default).id, subject_label: "Site settings"),
      event("media.updated", subject_type: "MediaAsset", subject_id: asset.id, subject_label: "tiny")
    ]
    routes = Audit::Sentence.for_events(events, viewer: @me, channel: :admin).map { |sentence| sentence.subject_route&.name }
    assert_equal %i[edit_admin_user_path edit_admin_group_path admin_settings_path admin_media_path], routes

    none = Audit::Sentence.for_events(events, viewer: audit_only_viewer, channel: :admin).map(&:subject_route)
    assert_equal [ nil, nil, nil, nil ], none
  end

  test "a page of events costs the same queries whatever the number of events" do
    viewer = @me
    counts = [ 2, 20 ].map do |n|
      events = []
      n.times do |i|
        post = as(@me) { create_post(title: "Q#{n}-#{i}", published: false) }
        page = as(@me) { create_page(title: "P#{n}-#{i}", published: false) }
        block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
        events += Audit::Event.where(subject: [ post, page, block ]).to_a
        events << event("session.created", subject_type: "User", subject_id: users(:two).id, subject_label: "two")
      end
      Audit::Sentence.for_events(events, viewer:, channel: :admin) # warm
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { Audit::Sentence.for_events(events, viewer:, channel: :admin) }
      queries
    end

    assert_equal counts.first, counts.last
  end

  test "it returns plain data: no HTML, nothing html_safe" do
    post = as(@me) { create_post(title: "<b>Bold</b>", published: false) }
    sentence = sentence_for(Audit::Event.find_by!(action: "post.created", subject: post))

    texts = [ sentence.subject_label, *sentence.parts.map(&:text) ]
    assert(texts.none? { |text| text.html_safe? })
    assert_includes texts, "<b>Bold</b>"
  end

  test "a publish of changes reads 'published changes to Pricing'" do
    page = create_page(title: "Pricing")
    post = as(@me) { create_post(title: "Hello", published: false) }

    assert_equal "You published changes to “Pricing”", read(sentence_for(event("page.changes_published", subject_type: "Page", subject_id: page.id, subject_label: "Pricing", metadata: { "number" => 2, "live_at" => Time.current.iso8601, "scheduled" => false })))
    assert_equal "You published changes to “Hello”", read(sentence_for(event("post.changes_published", subject_type: "Post", subject_id: post.id, subject_label: "Hello")))
  end

  test "one given a time reads 'scheduled changes to Pricing for 14 Oct'" do
    page = create_page(title: "Pricing")
    metadata = { "number" => 2, "live_at" => Time.utc(2026, 10, 14, 9).iso8601, "scheduled" => true }

    assert_equal "You scheduled changes to “Pricing” for 14 Oct", read(sentence_for(event("page.changes_published", subject_type: "Page", subject_id: page.id, subject_label: "Pricing", metadata: metadata)))
  end

  test "a take-over reads as having taken over editing, of a block on its page, of a page, of a post" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    post = as(@me) { create_post(title: "Hello", published: false) }

    assert_equal "You took over editing a block on “Pricing”", read(sentence_for(event("block.taken_over", subject_type: "ContentBlock", subject_id: block.id, subject_label: "Rich text block ##{block.id}")))
    assert_equal "You took over editing “Pricing”", read(sentence_for(event("page.taken_over", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You took over editing “Hello”", read(sentence_for(event("post.taken_over", subject_type: "Post", subject_id: post.id, subject_label: "Hello")))
  end

  test "an answered take-over reads as the actor having handed editing over, an unanswered one as having taken it" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    handed = { "from_user_id" => @me.id, "to_user_id" => users(:two).id, "answered" => true }
    passed = handed.merge("answered" => false)

    assert_equal "You handed over editing a block on “Pricing”", read(sentence_for(event("block.taken_over", subject_type: "ContentBlock", subject_id: block.id, subject_label: "x", metadata: handed)))
    assert_equal "You took over editing a block on “Pricing”", read(sentence_for(event("block.taken_over", subject_type: "ContentBlock", subject_id: block.id, subject_label: "x", metadata: passed)))
    assert_equal "You handed over editing “Pricing”", read(sentence_for(event("page.taken_over", subject_type: "Page", subject_id: page.id, subject_label: "Pricing", metadata: handed)))
    assert_equal "You handed over editing “Hello”", read(sentence_for(event("post.taken_over", subject_type: "Post", subject_id: 1, subject_label: "Hello", metadata: handed)))
    assert_equal "You took over editing “Hello”", read(sentence_for(event("post.taken_over", subject_type: "Post", subject_id: 1, subject_label: "Hello", metadata: passed)))
  end

  test "a note's events read as sentences about the record, a block's about its page" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_equal "You started a note on “Pricing”", read(sentence_for(event("note.started", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You replied to a note on “Pricing”", read(sentence_for(event("note.replied", subject_type: "ContentBlock", subject_id: block.id, subject_label: "Rich text block ##{block.id}")))
    assert_equal "You edited a note on “Pricing”", read(sentence_for(event("note.edited", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You deleted a note on “Pricing”", read(sentence_for(event("note.deleted", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You resolved a note on “Pricing”", read(sentence_for(event("note.resolved", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You pinned a note on “Pricing”", read(sentence_for(event("note.pinned", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You unpinned a note on “Pricing”", read(sentence_for(event("note.unpinned", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
    assert_equal "You removed the notes on “Pricing”", read(sentence_for(event("notes.removed", subject_type: "Page", subject_id: page.id, subject_label: "Pricing")))
  end
end
