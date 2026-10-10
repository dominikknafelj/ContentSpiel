require "test_helper"

# The people who have a record open (presence spec §5.1; every size, token,
# order and wording is the handoff's, `2026-10-10-presence-handoff.md`, by
# its item numbers below).
class Admin::PresenceScreen::PeopleComponentTest < ViewComponent::TestCase
  include ContentHelper

  NOW = Time.zone.local(2026, 10, 10, 12, 0, 0)

  setup do
    @record = create_page(title: "Pricing")
    @viewer = users(:one)
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @reader = users(:reader).tap { |user| user.update!(name: nil) }
  end

  def person(name, email = "#{name.parameterize}@example.com") = User.create!(name:, email_address: email, password: "a-long-password-1")

  def mark(user, record = @record, state: "here", arrived: NOW - 1.minute, since: arrived, tab: "tab-#{user.id}-#{SecureRandom.hex(3)}")
    Presence::Mark.insert!({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, token: SecureRandom.hex(8), state:, seen_at: NOW, arrived_at: arrived, state_at: since }) # version: none (a test of presence)
  end

  def render_people(record = @record, viewer: @viewer, **options)
    travel_to(NOW) { render_inline(Admin::PresenceScreen::PeopleComponent.new(record:, viewer:, **options)) }
  end

  def frame = "turbo-frame#presence-page-#{@record.id}"

  test "nobody else: the script's element and the empty frame, taking no room, and no group" do
    mark(@viewer)

    render_people

    assert_selector "div.hidden[data-controller='admin--presence--record'][data-live-part=waiting]" \
                    "[data-admin--presence--record-kind-value=page][data-admin--presence--record-id-value='#{@record.id}']" \
                    "[data-admin--presence--record-url-value='/cs-studio/presence/page/#{@record.id}']", visible: :all
    assert_selector "#{frame}[data-admin--presence--record-target=frame]", visible: :all
    assert_no_selector "#{frame} *", visible: :all
    assert_no_selector "[role=group]", visible: :all
    # Shown only while it holds a group: the element is a flex item of the
    # header's action row, and an empty one would still cost the row's gap.
    assert_includes page.find("div[data-controller]", visible: :all)[:class].split, "has-[[role=group]]:flex"
  end

  test "one person here: the actor avatar at 24px with a paper ring, their name and state as label and tooltip, never a title (1, 3, 7, 8)" do
    mark(@dana)

    render_people

    assert_selector "#{frame} [role=group][aria-label='Also open by 1 person']"
    assert_selector "[role=group] > [data-presence-user='#{@dana.id}'][data-presence-state=here][role=img][tabindex='0'][aria-label='Dana Weiss · here']", count: 1
    circle = page.find("[data-presence-user='#{@dana.id}']")
    circle.assert_selector "span.size-6.rounded-full.border.border-line-strong.bg-sunken.text-ink.font-cs-mono.ring-2.ring-paper[aria-hidden=true]", text: "DW", exact_text: true
    circle.assert_selector "span.text-\\[9px\\]", text: "DW"
    circle.assert_selector "[data-tooltip][aria-hidden=true]", text: "Dana Weiss · here", exact_text: true, visible: :all
    assert_no_selector "[title]", visible: :all
    assert_no_selector "[aria-live], [role=status], [role=alert]", visible: :all
    assert_no_selector "[role=group] button", visible: :all
  end

  test "one person away: the same circle unfilled, with how long (4, 7)" do
    mark(@dana, state: "away", arrived: NOW - 40.minutes, since: NOW - 12.minutes - 59.seconds)

    render_people

    assert_selector "[data-presence-user='#{@dana.id}'][data-presence-state=away][aria-label='Dana Weiss · away 12 min']"
    circle = page.find("[data-presence-user='#{@dana.id}']")
    circle.assert_selector "span.size-6.rounded-full.border.border-line.bg-paper.text-meta[aria-hidden=true]", text: "DW"
    circle.assert_no_selector ".bg-sunken, .border-line-strong, .text-ink:not([data-tooltip])"
    circle.assert_selector "[data-tooltip]", text: "Dana Weiss · away 12 min", exact_text: true, visible: :all
    # No status dot and no lowered opacity (4).
    assert_no_selector "[class*='opacity-'], [class*='bg-ok']"
  end

  test "away is counted in whole minutes, rounded down, and is over an hour from sixty (7)" do
    { 20.seconds => "away 0 min", 60.seconds => "away 1 min", 59.minutes + 59.seconds => "away 59 min",
      60.minutes => "away over an hour", 5.hours => "away over an hour" }.each do |ago, words|
      Presence::Mark.delete_all # version: none (a test of presence)
      mark(@dana, state: "away", arrived: NOW - 6.hours, since: NOW - ago)
      render_people
      assert_selector "[data-presence-user][aria-label='Dana Weiss · #{words}']", count: 1
    end
  end

  test "a person with no name is the part of the address before the at sign (7)" do
    mark(@reader)

    render_people

    name = @reader.email_address.split("@").first
    assert_selector "[data-presence-user='#{@reader.id}'][aria-label='#{name} · here']"
    assert_no_text @reader.email_address
  end

  test "here before away, each in order of arrival, each circle over the one before by 6px (1, 5)" do
    late = person("Late Here")
    mark(@dana, state: "away", arrived: NOW - 30.minutes, since: NOW - 3.minutes)
    mark(late, arrived: NOW - 1.minute)
    mark(@reader, arrived: NOW - 10.minutes)

    render_people

    circles = page.all("[role=group] > [data-presence-user]")
    assert_equal [ @reader.id, late.id, @dana.id ].map(&:to_s), circles.map { |each| each["data-presence-user"] }
    assert_equal [ false, true, true ], circles.map { |each| each[:class].split.include?("-ml-1.5") }
    assert_selector "[role=group][aria-label='Also open by 3 people']"
    # Three fit: no "+N" from 1024px.
    assert_no_selector "[data-presence-more=wide]", visible: :all
    assert_selector "[role=group] > .lg\\:hidden button", count: 1, visible: :all
  end

  test "four people: three circles and +1, which opens the list of all four in order (6)" do
    others = [ person("Ann One"), person("Bob Two"), person("Cy Three") ]
    others.each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }
    mark(@dana, state: "away", arrived: NOW - 50.minutes, since: NOW - 61.minutes)

    render_people

    assert_selector "[role=group][aria-label='Also open by 4 people']"
    assert_equal others.map { |user| user.id.to_s }, page.all("[role=group] > [data-presence-user]").map { |each| each["data-presence-user"] }
    assert_selector "[role=group] [data-controller='admin--ui--menu'] button[aria-expanded=false]", count: 1, visible: :all
    button = page.find("[role=group] button", visible: :all)
    assert_selector "[role=group] button.size-6.rounded-full.font-cs-mono.text-\\[10px\\].text-dim [data-presence-more=wide]", text: "+1", exact_text: true, visible: :all
    assert_not button.find(:xpath, "..")[:class].to_s.split.include?("-ml-1.5"), "the +N circle is not overlapped"
    rows = page.all("[role=list] [role=listitem] [data-presence-listed]", visible: :all)
    assert_equal (others + [ @dana ]).map { |user| user.id.to_s }, rows.map { |each| each["data-presence-listed"] }
    assert_equal [ "Ann One", "Bob Two", "Cy Three", "Dana Weiss" ], rows.map { |each| each.find("[data-presence-name]", visible: :all).text(:all) }
    assert_equal [ "here", "here", "here", "away over an hour" ], rows.map { |each| each.find("[data-presence-status]", visible: :all).text(:all) }
    assert_equal %w[AO BT CT DW], rows.map { |each| each.find("[aria-hidden=true]", visible: :all).text(:all) }
  end

  test "below 1024px the header shows one circle and the count of the rest, by classes alone (15)" do
    [ @dana, @reader, person("Ann One"), person("Bob Two") ].each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }

    render_people

    circles = page.all("[role=group] > [data-presence-user]")
    assert_equal [ false, true, true ], circles.map { |each| each[:class].split.include?("max-lg:hidden") }
    assert_selector "button [data-presence-more=wide].max-lg\\:hidden", text: "+1", exact_text: true, visible: :all
    assert_selector "button [data-presence-more=narrow].lg\\:hidden", text: "+3", exact_text: true, visible: :all
  end

  test "two or three people have no +N from 1024px and one below it" do
    mark(@dana, arrived: NOW - 5.minutes)
    mark(@reader, arrived: NOW - 4.minutes)

    render_people

    assert_selector "[role=group] > [data-presence-user]", count: 2
    assert_selector "[role=group] > .lg\\:hidden button [data-presence-more=narrow]", text: "+1", exact_text: true, visible: :all
    assert_no_selector "[data-presence-more=wide]", visible: :all
    assert_selector "[role=list] [data-presence-listed]", count: 2, visible: :all
  end

  test "one person has no +N at any width" do
    mark(@dana)

    render_people

    assert_no_selector "button, [role=list]", visible: :all
  end

  test "the panel's size: 20px circles, two and then +N, the same at every width (13)" do
    [ @dana, @reader, person("Ann One") ].each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }
    asset = create_media_asset
    Presence::Mark.update_all(record_type: "Media::Asset", record_id: asset.id) # version: none (a test of presence)

    render_people(asset, size: :panel)

    assert_selector "div.flex-none.ml-auto[data-controller='admin--presence--record'][data-admin--presence--record-kind-value=media]" \
                    "[data-admin--presence--record-url-value='/cs-studio/presence/media/#{asset.id}?size=panel']", visible: :all
    assert_selector "turbo-frame#presence-media-#{asset.id} [role=group][aria-label='Also open by 3 people']"
    assert_selector "[role=group] > [data-presence-user] > span.size-5.text-\\[8px\\][aria-hidden=true]", count: 2
    assert_no_selector "[role=group] > [data-presence-user].max-lg\\:hidden"
    assert_selector "button.size-5 [data-presence-more=wide]", text: "+1", exact_text: true, visible: :all
    assert_no_selector "[data-presence-more=narrow]", visible: :all
    assert_no_selector "[class~='lg:hidden'], [class~='max-lg:hidden']", visible: :all
    # At the window's right edge: the words and the list hang from the right.
    assert_selector "[data-presence-user] [data-tooltip].right-0", count: 2, visible: :all
    assert_selector "[role=list].right-0", visible: :all
  end

  test "the header's tooltips and its list hang from the left: its people are the first thing of a row that wraps to the window's left edge" do
    [ @dana, @reader ].each { |user| mark(user) }

    render_people

    assert_selector "[data-presence-user] [data-tooltip].left-0", count: 2, visible: :all
    assert_selector "[role=list].left-0", visible: :all
    assert_no_selector ".right-0", visible: :all
  end

  test "the frame alone, for the fetch that redraws it" do
    mark(@dana)

    render_people(frame_only: true)

    assert_no_selector "[data-controller='admin--presence--record']", visible: :all
    assert_selector "#{frame} [role=group] [data-presence-user='#{@dana.id}']"
  end

  test "the viewer is never shown, one person in two tabs is one circle, and a stale row is nobody (17)" do
    mark(@viewer)
    mark(@dana, state: "away", since: NOW - 4.minutes)
    mark(@dana)
    mark(@reader).then { Presence::Mark.where(user_id: @reader.id).update_all(seen_at: NOW - 151.seconds) } # version: none (a test of presence)

    render_people

    assert_selector "[data-presence-user]", count: 1
    assert_selector "[data-presence-user='#{@dana.id}'][data-presence-state=here]"
  end

  test "it takes what the hosts hand every slot component and ignores it, and an actor that is no user is shown nothing" do
    mark(@dana)

    render_people(data: nil, counts: { "total" => 3 }, locale: "en", url_options: {})
    assert_selector "[data-presence-user]", count: 1

    token = ApiToken.new(user: @viewer, name: "A token")
    render_people(viewer: token)
    assert_no_selector "*", visible: :all
    render_people(viewer: nil)
    assert_no_selector "*", visible: :all
  end

  test "an unknown size is refused" do
    assert_raises(KeyError) { Admin::PresenceScreen::PeopleComponent.new(record: @record, viewer: @viewer, size: :huge) }
  end

  test "it reads the roster in two statements at most, whatever the number of people" do
    [ @dana, @reader, person("Ann One"), person("Bob Two"), person("Cy Three") ].each { |user| mark(user) }

    statements = capture_sql { render_people }

    assert_operator statements.size, :<=, 2, statements.join("\n")
  end
end
