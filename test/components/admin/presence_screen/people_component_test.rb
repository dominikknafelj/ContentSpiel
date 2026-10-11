require "test_helper"

# The people who have a record open (presence spec §5.1; every size, token,
# order and wording is the handoff's, `2026-10-10-presence-handoff.md`, by
# its item numbers below; 18 to 26 are the decisions made once it was built).
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

  def group = "#{frame} button[data-admin--ui--menu-target=button]"

  def rows = page.all("[role=list] [role=listitem] [data-presence-listed]", visible: :all)

  test "nobody else: the script's element and the empty frame, taking no room, and no button" do
    mark(@viewer)

    render_people

    assert_selector "div.hidden[data-controller='admin--presence--record'][data-live-part=waiting]" \
                    "[data-admin--presence--record-kind-value=page][data-admin--presence--record-id-value='#{@record.id}']" \
                    "[data-admin--presence--record-url-value='/cs-studio/presence/page/#{@record.id}']", visible: :all
    assert_selector "#{frame}[data-admin--presence--record-target=frame]", visible: :all
    assert_no_selector "#{frame} *", visible: :all
    assert_no_selector "button, [role=list]", visible: :all
    # Shown only while it holds the group: the element is a flex item of the
    # header's action row, and an empty one would still cost the row's gap.
    assert_includes page.find("div[data-controller]", visible: :all)[:class].split, "has-[button]:flex"
  end

  test "one person here: the group is one button named for everyone in it, around the actor avatar at 24px with a paper ring and its tooltip (1, 3, 7, 23)" do
    mark(@dana)

    render_people

    assert_selector "#{group}[type=button][aria-label='Also open by 1 person: Dana Weiss, here'][aria-expanded=false]", count: 1
    # The focus ring is CS Studio's own shape, around the row (31); a pointer
    # cursor says the group is pressed (28).
    assert_selector "#{group}.cursor-pointer.rounded-cs.focus-visible\\:outline-2.focus-visible\\:outline-offset-2.focus-visible\\:outline-accent"
    assert_no_selector "#{group}.rounded-full"
    circle = page.find("#{group} > [data-presence-user='#{@dana.id}'][data-presence-state=here]")
    circle.assert_selector "span.size-6.rounded-full.border.border-line-strong.bg-sunken.text-ink.font-cs-mono.ring-2.ring-paper[aria-hidden=true]", text: "DW", exact_text: true
    circle.assert_selector "span.text-\\[9px\\]", text: "DW"
    # Its own tooltip, for the pointer; the circle itself is no Tab stop and
    # carries no name of its own: the button says it.
    assert_equal "admin--ui--tooltip", circle["data-controller"]
    circle.assert_selector "[data-tooltip][hidden][aria-hidden=true]", text: "Dana Weiss · here", exact_text: true, visible: :all
    assert_no_selector "[data-presence-user][tabindex], [data-presence-user][aria-label], [data-presence-user][role]", visible: :all
    assert_no_selector "[title]", visible: :all
    assert_no_selector "[aria-live], [role=status], [role=alert], [role=group]", visible: :all
    # One Tab stop, nothing interactive inside it.
    assert_selector "button, a, [tabindex='0']", count: 1, visible: :all
    assert_no_selector "button button, button a, button [tabindex]", visible: :all
    # No "+N", and still a list: of one.
    assert_no_selector "[data-presence-more]", visible: :all
    assert_selector "[role=list][tabindex='-1'][aria-label='Everyone with this open'][hidden] [role=listitem]", count: 1, visible: :all
  end

  test "one person away: the same circle unfilled, with how long (4, 7)" do
    mark(@dana, state: "away", arrived: NOW - 40.minutes, since: NOW - 12.minutes - 59.seconds)

    render_people

    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, away 12 min']"
    circle = page.find("[data-presence-user='#{@dana.id}'][data-presence-state=away]")
    circle.assert_selector "span.size-6.rounded-full.border.border-line.bg-paper.text-meta[aria-hidden=true]", text: "DW"
    circle.assert_no_selector ".bg-sunken, .border-line-strong"
    circle.assert_selector "[data-tooltip]", text: "Dana Weiss · away 12 min", exact_text: true, visible: :all
    # No status dot and no lowered opacity (4).
    assert_no_selector "[class*='opacity-'], [class*='bg-ok']", visible: :all
  end

  test "away is just now under a minute, then whole minutes rounded down, and over an hour from sixty (7, 26)" do
    { 0.seconds => "away just now", 59.seconds => "away just now", 60.seconds => "away 1 min", 119.seconds => "away 1 min",
      59.minutes + 59.seconds => "away 59 min", 60.minutes => "away over an hour", 5.hours => "away over an hour" }.each do |ago, words|
      Presence::Mark.delete_all # version: none (a test of presence)
      mark(@dana, state: "away", arrived: NOW - 6.hours, since: NOW - ago)
      render_people
      assert_selector "[data-presence-user] [data-tooltip]", text: "Dana Weiss · #{words}", exact_text: true, visible: :all
      assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, #{words}']"
      assert_equal [ words ], rows.map { |row| row.find("[data-presence-status]", visible: :all).text(:all) }
    end
    assert_no_text "0 min"
  end

  test "a person with no name is the part of the address before the at sign (7)" do
    mark(@reader)

    render_people

    name = @reader.email_address.split("@").first
    assert_selector "#{group}[aria-label='Also open by 1 person: #{name}, here']"
    assert_selector "[data-presence-user='#{@reader.id}'] [data-tooltip]", text: "#{name} · here", exact_text: true, visible: :all
    assert_no_text @reader.email_address
  end

  test "here before away, each in order of arrival, each circle over the one before by 6px (1, 5)" do
    late = person("Late Here")
    mark(@dana, state: "away", arrived: NOW - 30.minutes, since: NOW - 3.minutes)
    mark(late, arrived: NOW - 1.minute)
    mark(@reader, arrived: NOW - 10.minutes)

    render_people

    circles = page.all("#{group} > [data-presence-user]")
    assert_equal [ @reader.id, late.id, @dana.id ].map(&:to_s), circles.map { |each| each["data-presence-user"] }
    assert_equal [ false, true, true ], circles.map { |each| each[:class].split.include?("-ml-1.5") }
    assert_selector "#{group}[aria-label='Also open by 3 people: reader, here; Late Here, here; Dana Weiss, away 3 min']"
    # Three fit: no "+N" from 1024px.
    assert_no_selector "[data-presence-more=wide]", visible: :all
    assert_selector "#{group} > span.lg\\:hidden > [data-presence-more=narrow]", count: 1, visible: :all
  end

  test "four people: three circles and +1, a circle with no fill; the button names all four with how each is, and +1 is not spoken; the list is all four in order (6, 20, 21, 29)" do
    others = [ person("Ann One"), person("Bob Two"), person("Cy Three") ]
    others.each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }
    mark(@dana, state: "away", arrived: NOW - 50.minutes, since: NOW - 61.minutes)

    render_people

    assert_selector "#{group}[aria-label='Also open by 4 people: Ann One, here; Bob Two, here; Cy Three, here; Dana Weiss, away over an hour']"
    assert_equal others.map { |user| user.id.to_s }, page.all("#{group} > [data-presence-user]").map { |each| each["data-presence-user"] }
    more = page.find("#{group} > span:last-child")
    assert_equal %w[bg-paper border border-line-strong flex flex-none font-cs-mono items-center justify-center leading-none ml-1 rounded-full size-6 text-[10px] text-dim], more[:class].split.sort
    more.assert_selector "[data-presence-more=wide]", text: "+1", exact_text: true, visible: :all
    # A summary for the eye inside the one control: the name has everyone (29).
    assert_equal "true", more["aria-hidden"]
    # Hovering it shows the list; it is no button of its own.
    assert_equal "mouseenter->admin--ui--menu#reveal", more["data-action"]
    assert_equal (others + [ @dana ]).map { |user| user.id.to_s }, rows.map { |each| each["data-presence-listed"] }
    assert_equal [ "Ann One", "Bob Two", "Cy Three", "Dana Weiss" ], rows.map { |each| each.find("[data-presence-name]", visible: :all).text(:all) }
    assert_equal [ "here", "here", "here", "away over an hour" ], rows.map { |each| each.find("[data-presence-status]", visible: :all).text(:all) }
    assert_equal %w[AO BT CT DW], rows.map { |each| each.find("[aria-hidden=true]", visible: :all).text(:all) }
    # A row: a 24px avatar, the name in 14px ink, the status in 12px meta, 6px
    # by 8px; plain text, nothing in it takes the focus.
    assert_equal %w[flex gap-2 items-center px-2 py-1.5], rows.first[:class].split.sort
    rows.first.assert_selector "span.size-6[aria-hidden=true]", visible: :all
    rows.first.assert_selector "[data-presence-name].text-sm.text-ink", visible: :all
    rows.first.assert_selector "[data-presence-status].text-xs.text-meta", visible: :all
    assert_no_selector "[role=list] a, [role=list] button, [role=list] [tabindex]", visible: :all
  end

  test "six people: the button names all six, and nowhere says how many more (29)" do
    6.times { |index| mark(person("Person #{index}"), arrived: NOW - (20 - index).minutes) }

    render_people

    assert_selector "#{group}[aria-label='Also open by 6 people: Person 0, here; Person 1, here; Person 2, here; Person 3, here; Person 4, here; Person 5, here']"
    assert_no_text(/more (people|person)/)
    assert_no_selector "[aria-label*='more']", visible: :all
  end

  test "below 1024px the header shows one circle and the count of the rest, by classes alone (15)" do
    [ @dana, @reader, person("Ann One"), person("Bob Two") ].each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }

    render_people

    circles = page.all("#{group} > [data-presence-user]")
    assert_equal [ false, true, true ], circles.map { |each| each[:class].split.include?("max-lg:hidden") }
    assert_selector "#{group} [data-presence-more=wide].max-lg\\:hidden", text: "+1", exact_text: true, visible: :all
    assert_selector "#{group} [data-presence-more=narrow].lg\\:hidden", text: "+3", exact_text: true, visible: :all
  end

  test "two or three people have no +N from 1024px and one below it" do
    mark(@dana, arrived: NOW - 5.minutes)
    mark(@reader, arrived: NOW - 4.minutes)

    render_people

    assert_selector "#{group} > [data-presence-user]", count: 2
    assert_selector "#{group} > span.lg\\:hidden > [data-presence-more=narrow]", text: "+1", exact_text: true, visible: :all
    assert_no_selector "[data-presence-more=wide]", visible: :all
    assert_equal 2, rows.size
  end

  test "the panel's size: 20px circles with a ring in the surface colour, two and then +N on the surface, the same at every width (13, 20, 24)" do
    [ @dana, @reader, person("Ann One") ].each_with_index { |user, index| mark(user, arrived: NOW - (20 - index).minutes) }
    asset = create_media_asset
    Presence::Mark.update_all(record_type: "Media::Asset", record_id: asset.id) # version: none (a test of presence)

    render_people(asset, size: :panel)

    assert_selector "div.flex-none.ml-auto[data-controller='admin--presence--record'][data-admin--presence--record-kind-value=media]" \
                    "[data-admin--presence--record-url-value='/cs-studio/presence/media/#{asset.id}?size=panel']", visible: :all
    button = "turbo-frame#presence-media-#{asset.id} button"
    assert_selector "#{button}[aria-label='Also open by 3 people: Dana Weiss, here; reader, here; Ann One, here']"
    assert_selector "#{button} > span[aria-hidden=true] > [data-presence-more=wide]", visible: :all
    assert_selector "#{button} > [data-presence-user] > span.size-5.text-\\[8px\\].ring-2.ring-surface[aria-hidden=true]", count: 2
    assert_no_selector ".ring-paper", visible: :all
    assert_selector "#{button} > span.size-5.bg-surface.border-line-strong > [data-presence-more=wide]", text: "+1", exact_text: true, visible: :all
    assert_no_selector ".bg-paper", visible: :all
    assert_no_selector "[data-presence-more=narrow]", visible: :all
    assert_no_selector "[class~='lg:hidden'], [class~='max-lg:hidden']", visible: :all
    # The list hangs from the right there, and from the left in the header (19).
    assert_selector "[role=list].right-0", visible: :all
  end

  test "the header's list hangs from the left (19)" do
    [ @dana, @reader ].each { |user| mark(user) }

    render_people

    assert_selector "[role=list].left-0", visible: :all
    assert_no_selector ".right-0", visible: :all
  end

  test "the frame alone, for the fetch that redraws it" do
    mark(@dana)

    render_people(frame_only: true)

    assert_no_selector "[data-controller='admin--presence--record']", visible: :all
    assert_selector "#{group} [data-presence-user='#{@dana.id}']"
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
