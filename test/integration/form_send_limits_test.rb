require "test_helper"

# The rate limit on a visitor's sends (forms plan, decision 5;
# `Forms::SendLimit`): 5 per visitor in ten minutes, across every form, and
# 30 per form in ten minutes, from anyone. Owner's ruling 1 (pre-flight R1):
# a send over either is told so, a 429 with "Too many messages. Please try
# again in a few minutes." on the plain page and as `rate_limited` in the
# JSON, and stored nowhere. The visitor is counted by an HMAC of the
# address, so the cache holds no address.
class FormSendLimitsTest < ActionDispatch::IntegrationTest
  ANSWERS = { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com" }.freeze
  TOO_MANY = "Too many messages. Please try again in a few minutes.".freeze

  setup do
    clear_form_send_limits
    @form = forms(:contact)
  end

  def send_form(form = @form, from: "203.0.113.1", json: false, **extra)
    post form_send_path(form), params: { answers: ANSWERS, locale: "en", drawn: aged_drawn(form), website: "" }.merge(extra),
      env: { "REMOTE_ADDR" => from }, headers: json ? { "Accept" => "application/json" } : {}
  end

  def store_keys = Forms::SendLimit.store.instance_variable_get(:@data).keys

  test "the sixth send from one address in ten minutes is answered 429 with too many messages, and stored nowhere" do
    5.times { send_form }
    assert_response :ok
    assert_equal 5, Forms::Submission.count

    # Across forms: the visitor's count is the visitor's, not the form's.
    assert_no_difference [ "Forms::Submission.count", "Audit::Event.count" ] do
      send_form(forms(:newsletter), answers: { "f_mail0002" => "ada@example.com", "f_okay0002" => "1" })
      assert_response :too_many_requests
      assert_includes response.headers["Cache-Control"], "no-store"
      assert_nil response.headers["Set-Cookie"]
      assert_select "h1", text: "Too many messages"
      assert_select "main p", text: TOO_MANY
      assert_select "main a[href='/']"

      send_form(json: true)
      assert_response :too_many_requests
      assert_equal({ "status" => "rate_limited", "message" => TOO_MANY }, JSON.parse(response.body))
    end

    # Another visitor is not held back, and ten minutes on neither is this one.
    send_form(from: "203.0.113.2")
    assert_response :ok
    travel 11.minutes
    send_form
    assert_response :ok
  end

  test "the 31st send to one form in ten minutes, from many addresses, likewise: 429 and stored nowhere" do
    # Every send counts, spam too: a flood of honeypot sends fills the form's
    # limit as real ones would.
    30.times { |index| send_form(from: "198.51.100.#{index + 1}", website: "filled") }
    assert_response :ok
    assert_equal 0, Forms::Submission.count

    assert_no_difference [ "Forms::Submission.count", "Audit::Event.count" ] do
      send_form(from: "198.51.100.200")
      assert_response :too_many_requests
      assert_select "main p", text: TOO_MANY
    end

    # Another form is not held back by this one's flood.
    send_form(forms(:newsletter), from: "198.51.100.201", answers: { "f_mail0002" => "ada@example.com", "f_okay0002" => "1" })
    assert_response :ok
  end

  test "the cache key holds no address" do
    send_form(from: "203.0.113.7")

    keys = store_keys
    assert_equal [ "rate-limit:form_sends:form_send_form:#{@form.id}", "rate-limit:form_sends:form_send_visitor:#{Forms::SendLimit.visitor_key("203.0.113.7")}" ].sort, keys.sort
    assert keys.none? { |key| key.include?("203.0.113.7") }, keys.inspect
    assert_match(/\A\h{64}\z/, Forms::SendLimit.visitor_key("203.0.113.7"))
    assert_not_equal Forms::SendLimit.visitor_key("203.0.113.7"), Forms::SendLimit.visitor_key("203.0.113.8")
  end

  # One IPv6 visitor holds a whole /64 and may send from any address in it:
  # they are one counter. An IPv4 address is counted whole.
  test "two IPv6 addresses in one /64 share a counter, and the cache key still holds no address" do
    3.times { send_form(from: "2001:db8:1:2::a") }
    2.times { send_form(from: "2001:db8:1:2:ffff::b") }
    assert_response :ok
    send_form(from: "2001:db8:1:2:abcd:ef01:2345:6789")
    assert_response :too_many_requests

    send_form(from: "2001:db8:1:3::a")
    assert_response :ok, "the next /64 is another visitor"

    assert_equal Forms::SendLimit.visitor_key("2001:db8:1:2::a"), Forms::SendLimit.visitor_key("2001:db8:1:2:ffff::b")
    assert_not_equal Forms::SendLimit.visitor_key("203.0.113.7"), Forms::SendLimit.visitor_key("203.0.113.8")
    keys = store_keys
    assert_equal 3, keys.size, keys.inspect # the form, and two visitors
    # A hex digest can hold "db8" or "2001" by chance, so the shape is what is
    # asserted (a visitor key: no ':' after its own prefix and exactly 64 hex
    # characters), plus the literal addresses and prefixes the test used.
    addresses = ["203.0.113.1", "203.0.113.7", "203.0.113.8", "2001:db8:1:2::a", "2001:db8:1:2:ffff::b",
      "2001:db8:1:2:abcd:ef01:2345:6789", "2001:db8:1:3::a", "2001:db8:1:2", "2001:db8:1:3", "2001:db8", "2001:0db8"]
    keys.each { |key| addresses.each { |address| assert_not_includes key, address } }
    visitor_keys = keys.select { |key| key.include?("form_send_visitor") }
    assert_equal 2, visitor_keys.size, keys.inspect
    visitor_keys.each do |key|
      assert_match(/\A(?:rate-limit:form_sends:)?form_send_visitor:\h{64}\z/, key, "a visitor key is a prefix and a bare digest")
    end
  end
end
