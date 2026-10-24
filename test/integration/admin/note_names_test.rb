require "test_helper"

# A person without a name, as a note shows them (the handoff's decision 36):
# the part of their email address before the at sign, on every surface where
# a note names a person. `Notes.name_of` is the one place; `User#display_name`,
# which the rest of CS Studio uses, still answers the whole address.
class Admin::NoteNamesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @base = "/cs-studio/notes/page/#{@page.id}"
    # `two` has no name: two@example.com. `reader` has none either.
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]? Ask @[#{users(:one).id}]") }.record
    @note = @thread.first_message
    sign_in_as(users(:reader))
  end

  def frame = { "Turbo-Frame" => "notes" }

  test "a message's author line, its avatar and its mention chips say the part before the at sign" do
    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-message-#{@note.id}" do
      assert_select "strong .admin-user-name", text: "two"
      assert_select "[data-note-mention=viewer]", text: "@reader"
      assert_select "[data-note-mention=other]", text: "@one"
      assert_select "span[aria-hidden=true][class~='rounded-full']", text: "tw"
    end
    assert_no_match(/two@example\.com|reader@example\.com|one@example\.com/, response.body)
  end

  test "a name set later shows in the author line and in existing mentions" do
    users(:two).update!(name: "Dana Weiss")
    users(:one).update!(name: "Sam")

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-message-#{@note.id} strong .admin-user-name", text: "Dana Weiss"
    assert_select "[data-note-mention=other]", text: "@Sam"
  end

  test "the list's row, and the line saying who resolved a thread, name the person the same way" do
    get @base, headers: frame
    assert_select "#note-row-#{@thread.id} strong .admin-user-name", text: "two"
    assert_select "#note-row-#{@thread.id}", text: /@reader/

    as(users(:two)) { assert Notes::Resolve.call(@thread).ok? }
    get "#{@base}/threads/#{@thread.id}", headers: frame
    assert_select "[data-note-badge=resolved] .admin-user-name", text: "two"
  end

  test "an edit form shows a nameless person's mention by the short name and saves it as the same mention" do
    sign_in_as(users(:two))

    get "#{@base}/threads/#{@thread.id}", params: { edit: @note.id }, headers: frame

    assert_select "#note-message-#{@note.id} form[data-note-composer] textarea[name=body]", text: "Ready, @reader? Ask @one"
    names = JSON.parse(css_select("#note-message-#{@note.id} form[data-note-composer] input[name=mention_names]").first["value"])
    assert_equal({ "reader" => users(:reader).id, "one" => users(:one).id }, names)

    patch "#{@base}/threads/#{@thread.id}/messages/#{@note.id}", params: { body: "Ready now, @reader? Ask @one", mention_names: names.to_json }
    assert_equal "Ready now, @[#{users(:reader).id}]? Ask @[#{users(:one).id}]", @note.reload.body
  end

  test "the inbox sentence, its excerpt, the toast's delivery and Open threads name the person by the short name" do
    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you [data-inbox-sentence]", text: "two mentioned you"
    assert_select "turbo-frame#notes-for-you [data-inbox-excerpt]", text: /Ready, @reader\? Ask @one/
    assert_select "turbo-frame#notes-open-threads a[data-open-thread-row]", text: /Page · two · /

    delivery = Notes::Delivery.find_by!(user: users(:reader), thread: @thread)
    get "/cs-studio/notes/deliveries/#{delivery.id}", headers: { "Accept" => "application/json" }
    assert_equal [ "two mentioned you", "Ready, @reader? Ask @one" ], response.parsed_body.values_at("sentence", "excerpt")
  end

  test "a reaction's hover title and its spoken name list people by the short name" do
    as(users(:two)) { Notes::React.call(@note, emoji: "🎉", on: true) }

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-message-#{@note.id} button[data-reaction='🎉'][title='two']"
    assert_select "#note-message-#{@note.id} button[data-reaction='🎉'][aria-label$='by two']"
  end

  test "the mind graph card's rows name the author by the short name" do
    article = create_post(title: "Hello")
    as(users(:two)) { Notes::Start.call(article, body: "For @[#{users(:reader).id}]") }

    get "/cs-studio/notes/post/#{article.id}/threads", headers: { "Accept" => "application/json" }

    assert_equal [ [ "two", "For @reader" ] ], response.parsed_body["threads"].map { |row| row.values_at("author", "text") }
  end

  test "the mention picker shows the short name and still the whole address on its second line" do
    get "#{@base}/mentions", params: { q: "two@" }

    assert_equal [ { "id" => users(:two).id, "label" => "two", "hint" => "two@example.com", "initials" => "tw" } ], response.parsed_body
  end

  test "the rest of CS Studio names a nameless user by the whole address, as before" do
    assert_equal "two@example.com", users(:two).display_name
    assert_equal "two@example.com", Admin::Ui::UserNameComponent.new(user: users(:two)).label
    assert_equal "two", Notes.name_of(users(:two))
    users(:two).update!(name: "Dana")
    assert_equal "Dana", Notes.name_of(users(:two))
  end
end
