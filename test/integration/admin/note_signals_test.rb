require "test_helper"

# Live delivery as a request sees it (notes spec §6): the tab's own id comes
# in on a header and goes out in the record's signal, and the cable is one
# address that the public site neither serves nor mentions.
class Admin::NoteSignalsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @base = "/cs-studio/notes/page/#{@page.id}"
    @stream = Notes::Signals.record_stream("Page", @page.id)
  end

  def sent = broadcasts(@stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  test "a note's signal names the tab whose request wrote it" do
    sign_in_as(users(:reader))

    post "#{@base}/threads", params: { body: "Is this right?" }, headers: { "X-Notes-Tab" => "0f8fad5b-d9cb-469f-a165-70867728950e" }
    thread = Notes::Thread.order(:id).last
    post "#{@base}/threads/#{thread.id}/messages", params: { body: "Yes" }, headers: { "X-Notes-Tab" => "another-tab-1" }

    assert_equal [ { "kind" => "threads", "thread_id" => thread.id, "origin" => "0f8fad5b-d9cb-469f-a165-70867728950e" },
      { "kind" => "threads", "thread_id" => thread.id, "origin" => "another-tab-1" } ], sent
  end

  # The header is the client's: only an id of the expected shape is echoed,
  # and one request's id never reaches the next request's signal.
  test "a tab id of any other shape is dropped, and the note is written all the same" do
    sign_in_as(users(:reader))

    [ "<img src=x>", "A sentence for everyone", "x" * 41, "short", "UPPER-CASE-ID" ].each do |junk|
      post "#{@base}/threads", params: { body: "Is this right?" }, headers: { "X-Notes-Tab" => junk }
      assert_response :see_other
    end
    post "#{@base}/threads", params: { body: "Is this right?" }

    assert_equal 6, sent.size
    assert_equal [ %w[kind thread_id] ], sent.map(&:keys).uniq
  end

  test "a refused note sends nothing" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password-password")
    sign_in_as(stranger)

    assert_no_broadcasts(@stream) do
      post "#{@base}/threads", params: { body: "Hello" }, headers: { "X-Notes-Tab" => "tab-12345678" }
    end
    assert_response :not_found
  end

  # `/cable` is Action Cable's own mount (`config.action_cable.mount_path`),
  # drawn ahead of every route of the app: the public catch-all never sees
  # it, so it is neither a page's address nor a 404 from the theme, and the
  # setup redirect does not catch it either. A plain request is refused by
  # Action Cable itself; a WebSocket is refused by the connection without a
  # CS Studio session (`test/channels/application_cable/connection_test.rb`).
  test "the cable's address is Action Cable's own, not the public site's" do
    create_page(title: "cable", published: true)

    get "/cable"
    assert_response :not_found
    assert_equal "Page not found", response.body
    assert_nil response.headers["Set-Cookie"]

    post "/cable", params: { command: "subscribe" }
    assert_equal "Page not found", response.body

    assert_includes ContentSpiel::RESERVED_PATHS, "cable"
  end

  test "a public page loads and names nothing of the cable" do
    create_page(title: "About")

    get "/"

    assert_response :success
    assert_no_match(/action-cable|actioncable|\/cable|turbo-cable-stream-source/i, response.body)
  end
end
