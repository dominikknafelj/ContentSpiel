require "test_helper"

# The overview the publish dialog shows (drafts spec §3), worded from
# `Publishing::Changes`.
class Admin::EditorScreen::ChangesOverviewComponentTest < ViewComponent::TestCase
  include ContentHelper

  # `@pricing`, not `@page`: `render_inline` keeps its result in `@page`.
  setup do
    @pricing = create_page(title: "Pricing", published: false)
    @changed, @removed, @stays = %w[One Two Three].map { |text| add(text) }
    assert Pages::Save.call(@pricing, attributes: { published: true }).ok?
    @me = users(:one)
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
  end

  def add(text)
    ContentBlocks::Save.call(ContentBlock.new(owner: @pricing), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc(text) } }).record
  end

  def edit
    assert ContentBlocks::Save.call(@changed, translations: { "en" => { body: rich_doc("One, changed") } }).ok?
    @added = add("Four")
    assert ContentBlocks::Destroy.call(@removed).ok?
    assert Pages::Save.call(@pricing, translations: { "de" => { subtitle: "Preise und Pläne" } }).ok?
  end

  def overview(record = @pricing, lost: [], viewer: @me)
    as(viewer) do
      render_inline Admin::EditorScreen::ChangesOverviewComponent.new(record: record.reload, changes: Publishing::Changes.of(record), lost: lost,
        holds: Editing::Holds.on(record, viewer: viewer, tab: "tab-aaaaaaaa"), locale: "en")
    end
  end

  test "each changed, added, removed and moved block is one row with its kind and its type" do
    edit
    overview

    assert_selector "[data-change=changed]", text: "Rich text"
    assert_selector "[data-change=changed]", text: "One, changed"
    assert_selector "[data-change=added]", text: "Rich text"
    assert_selector "[data-change=removed]", text: "Two"
    assert_selector "[data-change]", count: 3
  end

  test "a block that only changed place is Moved" do
    assert ContentBlocks::Reorder.call(@pricing, [ @stays.id, @changed.id, @removed.id ]).ok?
    overview

    assert_selector "[data-change=moved]", count: 1
    assert_selector "[data-change]", count: 1
    assert_selector "[data-change=moved] span.uppercase", text: "Moved"
  end

  test "the record's changed fields are named by their labels, and tags as Tags" do
    edit
    overview
    assert_selector "h3", text: "Page"
    assert_selector "[data-changed-fields]", text: "Subtitle"

    post = create_post(title: "Post", tags: %w[one])
    assert Posts::Save.call(post, attributes: { tag_names: %w[two] }, translations: { "en" => { excerpt: "Short" } }).ok?
    overview(post)
    assert_selector "h3", text: "Post"
    assert_selector "[data-changed-fields]", text: "Excerpt and Tags"
  end

  test "the languages in which anything changed are named" do
    edit
    overview

    assert_selector "[data-changed-languages]", text: "German and English"
  end

  test "with nothing changed it says so and lists nothing" do
    overview

    assert_text "Nothing to publish. This is the same as what is published."
    assert_selector "[data-publishing-overview][data-nothing]"
    assert_no_selector "[data-change]"
  end

  test "when another tab holds a block it says that only what has been saved is published, naming the person" do
    edit
    overview
    assert_no_selector "[data-publishing-held]"

    reserve(@changed, @pricing, @dana, "tab-bbbbbbbb")
    overview
    assert_selector "[data-publishing-held]", count: 1, text: "Dana Weiss is editing this page. Only what has been saved is published."
  end

  test "my own hold in this tab is no such line, and my own other tab is" do
    edit
    reserve(@changed, @pricing, @me, "tab-aaaaaaaa")
    overview
    assert_no_selector "[data-publishing-held]"

    reserve(@stays, @pricing, @me, "tab-cccccccc")
    overview
    assert_selector "[data-publishing-held]", count: 1
  end

  test "compared with changes that are scheduled, it says which" do
    edit
    publish_changes(@pricing, at: Time.zone.local(2031, 10, 12, 9))
    assert Pages::Save.call(@pricing, translations: { "en" => { title: "Later still" } }).ok?
    overview

    assert_text "Compared with the changes scheduled for 12 Oct 2031, 09:00."
    assert_selector "[data-changed-fields]", text: "Title"
    assert_no_selector "[data-change]"
  end

  test "with nothing changed since a change was scheduled, it says it is the same as what is scheduled" do
    edit
    publish_changes(@pricing, at: Time.zone.local(2031, 10, 12, 9))
    overview

    assert_text "Nothing new to publish. This is the same as the changes scheduled for 12 Oct 2031, 09:00."
    assert_no_text "the same as what is published"
    assert_no_selector "[data-change]"
  end

  test "the records that would lose their address are named once each, by title, with a link to their editor, their address and the languages" do
    edit
    post = create_post(title: "Hello")
    lost = %w[en de].map { |locale| { record_type: "Post", record_id: post.id, locale: locale, path: "/blog/hello" } }
    overview(lost: lost)

    assert_selector "[data-publishing-lost-addresses] h3", text: "Addresses"
    assert_text "When this page is published, these lose their address and show “not found” on the site:"
    assert_selector "[data-lost-address]", count: 1
    assert_selector "[data-lost-address] a[href='/cs-studio/posts/#{post.id}'][data-turbo-frame=_top]", text: "Hello"
    assert_selector "[data-lost-address]", text: "/blog/hello"
    assert_selector "[data-lost-address]", text: "(DE and EN)"
    assert_no_selector "[data-publishing-own-address]"
    assert_no_text "cannot be published"
  end

  test "a record the viewer may not read is counted, not named" do
    edit
    hidden = create_post(title: "Secret plans")
    lost = [ { record_type: "Post", record_id: hidden.id, locale: "en", path: "/blog/secret-plans" } ]
    overview(lost: lost, viewer: users(:editor_branch))

    assert_no_text "Secret plans"
    assert_no_selector "[data-lost-address]"
    assert_selector "[data-publishing-lost-addresses]", text: "1 more that you can’t open"
  end

  test "the record's own address is the refusal, said as one" do
    edit
    overview(lost: [ { record_type: "Page", record_id: @pricing.id, locale: "en", path: "/pricing" } ])

    assert_selector "[data-publishing-own-address][role=alert]", text: "This page would lose its own address, /pricing (EN)"
    assert_no_selector "[data-publishing-lost-addresses]"
  end

  test "everything is inside one element with no id, which the dialog puts into its overview" do
    edit
    reserve(@changed, @pricing, @dana, "tab-bbbbbbbb")
    overview

    assert_selector "body > [data-publishing-overview]", count: 1
    assert_no_selector "[id]"
    assert_no_selector "turbo-frame"
  end

  test "a name is text, whatever was typed as one" do
    edit
    @dana.update!(name: "<b>Dana</b>")
    reserve(@changed, @pricing, @dana, "tab-bbbbbbbb")
    overview

    assert_no_selector "[data-publishing-held] b"
    assert_selector "[data-publishing-held]", text: "<b>Dana</b>"
  end
end
