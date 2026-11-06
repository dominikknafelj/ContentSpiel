require "test_helper"

# The endpoint a visitor's form posts to: with JavaScript it answers
# JSON for the script to write in place, without it a plain page of the
# CMS's own (`layouts/form_send`), never the theme's. It is no
# `PublicController` and is never cached, but it keeps the public wall
# (`Cookieless`): no session, no token, no cookie. The visitor
# (`AccessControl::VISITOR`) is its only actor.
class FormSendsTest < ActionDispatch::IntegrationTest
  include LogCapture

  ANSWERS = { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com", "f_text0001" => "Hello from the form" }.freeze

  setup do
    clear_form_send_limits
    @form = forms(:contact)
    @page = Current.set(actor: users(:one)) { create_page(title: "Contact us") }
    place_form(@page, @form)
  end

  def send_form(form = @form, answers: ANSWERS, json: false, drawn: aged_drawn(form), page: @page, locale: "en", **extra)
    post form_send_path(form), params: { answers: answers, locale: locale, page_id: page&.id, drawn: drawn, website: "" }.merge(extra),
      headers: json ? { "Accept" => "application/json" } : {}
  end

  def answer = JSON.parse(response.body)

  def counts = [ Forms::Submission.count, Forms::Delivery.count, Audit::Event.count ]

  def assert_nothing_written
    before = counts
    yield
    assert_equal before, counts, "no submission, delivery or event"
  end

  def assert_back_link(href)
    assert_select "main a[href='#{href}']", text: "← #{I18n.t("public.forms.back")}"
  end

  test "a valid send without JavaScript answers the thank-you page with a link back, 200, no-store, and no Set-Cookie" do
    assert_difference -> { Forms::Submission.count }, 1 do
      send_form
    end

    assert_response :ok
    assert_equal "text/html", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_nil response.headers["Set-Cookie"]
    assert_empty cookies.to_hash
    assert_select "html[lang=en]"
    assert_select "head title", text: "#{I18n.t("public.forms.pages.sent")} · Test Site"
    assert_select "meta[name=robots][content=noindex]"
    assert_select "meta[name=csrf-token], meta[name=csrf-param], script[type=importmap]", count: 0
    assert_select "h1", text: I18n.t("public.forms.pages.sent")
    assert_select "[role=status]", text: "Thank you, we'll be in touch."
    assert_back_link "/contact-us"
    assert_select "header a[href='/contact-us']", text: "Test Site"
    assert_no_match(/CONTENT·SPIEL|sign-in/, response.body)

    submission = Forms::Submission.last
    assert_equal [ @form, @page, "en" ], [ submission.form, submission.page, submission.locale ]
  end

  test "the JSON answer is the thank-you in the visitor's language, falling back to English for the CMS's words" do
    assert Locales.enabled?("de"), "the fixture site has German"
    @form.update_columns(thank_you: { "en" => "Thank you.", "de" => "Danke, wir melden uns." }) # version: none (a test's form)

    send_form(json: true, locale: "de")
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_nil response.headers["Set-Cookie"]
    assert_equal({ "status" => "sent", "message" => "Danke, wir melden uns." }, answer)
    assert_equal "de", Forms::Submission.last.locale

    # No thank-you of the form's own: the CMS's sentence, in English since
    # German has no file of the public words.
    @form.update_columns(thank_you: {}) # version: none (a test's form)
    send_form(json: true, locale: "de")
    assert_equal({ "status" => "sent", "message" => I18n.t("public.forms.sent") }, answer)
    assert_equal "Thank you. Your answers have been sent.", answer["message"]

    # A language the site has not switched on is the default's.
    send_form(json: true, locale: "fr")
    assert_equal "en", Forms::Submission.last.locale
  end

  test "the admin layout's html carries no data-surface" do
    sign_in_as users(:one)
    get "/cs-studio"

    assert_response :success
    assert_select "html"
    assert_select "html[data-surface]", count: 0
  end

  test "invalid answers redraw the form with the errors linked from the summary and the typed values, 422" do
    drawn = aged_drawn(@form)

    assert_nothing_written do
      send_form(answers: ANSWERS.merge("f_name0001" => " ", "f_mail0001" => "not-an-address"), drawn: drawn)
    end

    assert_response :unprocessable_content
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_nil response.headers["Set-Cookie"]
    assert_select "html[data-surface=plain]"
    assert_select "h1", text: I18n.t("public.forms.pages.invalid")
    assert_select "[role=alert][tabindex='-1'][autofocus]" do
      assert_select "p", text: "Please correct 2 answers."
      assert_select "a[href='#form-send-f_name0001']", text: "Your name: Please fill in this field."
      assert_select "a[href='#form-send-f_mail0001']", text: "Email address: Please check this entry."
      assert_select "a", count: 2
    end

    assert_select "form.form-send-page__form[action='#{form_send_path(@form)}'][method=post]" do
      assert_select "input[name=authenticity_token]", count: 0
      assert_select "input#form-send-f_name0001[aria-invalid=true][aria-describedby='form-send-f_name0001-error']"
      assert_select "#form-send-f_name0001-error", text: "Please fill in this field."
      assert_select "input#form-send-f_mail0001[value='not-an-address'][aria-invalid=true]"
      assert_select "textarea#form-send-f_text0001", text: "Hello from the form"
      assert_select "textarea#form-send-f_text0001[aria-invalid]", count: 0
      assert_select "input[type=hidden][name=drawn][value='#{drawn}']"
      assert_select "input[type=hidden][name=locale][value=en]"
      assert_select "input[type=hidden][name=page_id][value='#{@page.id}']"
      assert_select "[hidden][aria-hidden=true] input[name=website][tabindex='-1'][autocomplete=off]"
      assert_select "button[type=submit]", text: "Send"
    end
    assert_back_link "/contact-us"

    # A radio group is linked at its first radio (a fieldset takes no
    # focus), the box unticked and the choice not one of the choices.
    newsletter = forms(:newsletter)
    signup = Current.set(actor: users(:one)) { create_page(title: "Sign up") }
    place_form(signup, newsletter)
    send_form(newsletter, answers: { "f_mail0002" => "ada@example.com", "f_topic002" => "c_bogus0001" }, page: signup)
    assert_response :unprocessable_content
    assert_select "[role=alert]" do
      assert_select "a[href='#form-send-f_topic002-c_news0001']", text: "Topic: Please choose one of the options."
      assert_select "a[href='#form-send-f_okay0002']", text: "I agree to receive the newsletter: Please fill in this field."
    end
    assert_select "fieldset input[type=radio][aria-invalid=true]", count: 2
    assert_select "input[type=checkbox]#form-send-f_okay0002:not([checked])"
    assert_select "button[type=submit]", text: "Subscribe"
    assert_back_link "/sign-up"

    send_form(answers: ANSWERS.merge("f_name0001" => ""), json: true)
    assert_response :unprocessable_content
    assert_equal({ "status" => "invalid", "summary" => "Please correct 1 answer.",
                   "errors" => [ { "key" => "f_name0001", "message" => "Please fill in this field.", "item" => "Your name: Please fill in this field." } ] }, answer)
  end

  # The redrawn page hands back the token the visitor sent,
  # so a correction sent within three seconds of that page is not dropped as
  # too fast. A fresh token would make this send `:too_soon`: answered as a
  # success and stored nowhere.
  # A gem taken out leaves its field types dormant. The redrawn page shows
  # what the Form block showed: the registered fields only, never a 500 for
  # the dormant one.
  test "an invalid send without JavaScript to a form holding a dormant field redraws the registered fields, 422" do
    @form.update_columns(fields: @form.fields.map(&:to_h) + [ { "key" => "f_star0001", "type" => "acme/gone", "required" => true, "label" => { "en" => "Stars" } } ]) # version: none (a test's row)

    send_form(answers: ANSWERS.merge("f_name0001" => ""))

    assert_response :unprocessable_content
    assert_select "form.form-send-page__form" do
      assert_select "input#form-send-f_name0001[aria-invalid=true]"
      assert_select "[id^='form-send-f_star0001']", count: 0
    end
  end

  test "the error page carries the first token: a correction sent a second later is kept" do
    first = Forms::Drawn.token(@form, at: Time.current - Forms::Drawn::MIN_SECONDS)
    send_form(answers: ANSWERS.merge("f_name0001" => ""), drawn: first)
    assert_response :unprocessable_content
    carried = css_select("input[name=drawn]").sole["value"]
    assert_equal first, carried

    travel 1.second
    assert_difference -> { Forms::Submission.count }, 1 do
      send_form(drawn: carried)
    end
    assert_response :ok
  end

  test "a send to a trashed or missing form is a 404 page with a link back, and writes nothing" do
    assert Current.set(actor: users(:one), channel: :admin) { Trash::Move.call(@form) }.ok?

    assert_nothing_written do
      send_form
      assert_response :not_found
      assert_select "h1", text: I18n.t("public.forms.pages.gone")
      assert_select "main p", text: "This form is no longer available."
      assert_back_link "/contact-us"
      assert_includes response.headers["Cache-Control"], "no-store"

      send_form(json: true)
      assert_response :not_found
      assert_equal({ "status" => "gone", "message" => "This form is no longer available." }, answer)

      post form_send_path(form_id: 0), params: { answers: ANSWERS, page_id: @page.id }
      assert_response :not_found
      assert_back_link "/"
    end
  end

  test "no keys and mail not ready is a 503 that says try again later, and writes nothing" do
    with_mail_state(:not_set_up) do
      without_encryption_keys do
        assert_nothing_written do
          send_form
          assert_response :service_unavailable
          assert_select "h1", text: I18n.t("public.forms.pages.unavailable")
          assert_select "main p", text: "This form can't take answers at the moment. Please try again later."
          assert_back_link "/contact-us"

          send_form(json: true)
          assert_response :service_unavailable
          assert_equal({ "status" => "unavailable", "message" => I18n.t("public.forms.unavailable") }, answer)
        end
      end
    end

    # Without keys there are no answers whatever mail does.
    with_mail_state(:working) do
      without_encryption_keys do
        assert_nothing_written { send_form(json: true) }
        assert_response :service_unavailable
      end
    end
  end

  # What an unknown form answers, by `Accept`: the reference a refused send
  # is held to, status, type and body alike, so a probe learns nothing from
  # the answer about a form that exists but takes no sends.
  def unknown_form_answer(json:, locale: "en")
    post form_send_path(form_id: 0), params: { answers: ANSWERS, locale: locale, page_id: @page.id, drawn: aged_drawn(@form), website: "" },
      headers: json ? { "Accept" => "application/json" } : {}
    assert_response :not_found
    [ response.status, response.media_type, response.body ]
  end

  def assert_refused_as_unknown(label, form: @form, **send)
    expected = [ unknown_form_answer(json: false), unknown_form_answer(json: true) ]
    assert_nothing_written do
      actual = [ false, true ].map do |json|
        send_form(form, json: json, **send)
        [ response.status, response.media_type, response.body ]
      end
      assert_equal expected, actual, label
    end
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_nil response.headers["Set-Cookie"]
  end

  # The owner's rule (2026-11-05, review M-2): a form takes a send only when
  # it has a field a visitor is drawn AND the send names a live page whose
  # published copy places it (`Forms::Placements.live_page`). Anything else
  # is answered as a form that does not exist and stores, mails and records
  # nothing; so every submission is made with its page.
  test "a form with no field a visitor is drawn is refused as an unknown form is" do
    @form.update_columns(fields: []) # version: none (a test's row)
    assert_refused_as_unknown("no fields")

    # Only a dormant field (a gem taken out): the block draws nothing either.
    clear_form_send_limits # four sends a case: six from one address at most
    @form.update_columns(fields: [ { "key" => "f_star0001", "type" => "acme/gone", "required" => false, "label" => { "en" => "Stars" } } ]) # version: none (a test's row)
    assert_refused_as_unknown("only a dormant field")
  end

  test "a send that names no live page placing the form is refused as an unknown form is" do
    clear_form_send_limits
    draft = Current.set(actor: users(:one)) { create_page(title: "Draft contact", published: false) }
    place_form(draft, @form, publish: false)
    elsewhere = Current.set(actor: users(:one)) { create_page(title: "Elsewhere") }
    unpublished_block = Current.set(actor: users(:one)) { create_page(title: "Not yet") }
    place_form(unpublished_block, @form, publish: false)

    { "a draft page" => { page: draft }, "a live page that does not place it" => { page: elsewhere },
      "a live page with the form only in its unpublished changes" => { page: unpublished_block },
      "no page" => { page: nil }, "a page id that is no number" => { page: nil, page_id: "not-a-number" },
      "no page, the honeypot filled: refused before the spam measures" => { page: nil, website: "https://spam.example" } }.each do |label, send|
      clear_form_send_limits # four sends a case: six from one address at most
      assert_refused_as_unknown(label, **send)
    end
  end

  test "a send from a page in the trash, or for a form placed on no page at all, is refused as an unknown form is" do
    unplaced = forms(:newsletter)
    newsletter = { "f_mail0002" => "ada@example.com", "f_okay0002" => "1" }
    assert_refused_as_unknown("a form placed nowhere, naming no page", form: unplaced, answers: newsletter, page: nil)
    clear_form_send_limits
    assert_refused_as_unknown("a form placed nowhere, naming a live page of another form", form: unplaced, answers: newsletter)

    clear_form_send_limits
    assert Current.set(actor: users(:one), channel: :admin) { Trash::Move.call(@page) }.ok?
    assert_refused_as_unknown("a trashed page")
  end

  test "every stored submission carries the live page it was sent from" do
    send_form(locale: "de")
    assert_response :ok
    submission = Forms::Submission.last
    assert_equal @page.id, submission.page_id
    assert_select "html[lang=de]"
  end

  test "a tripped honeypot, a send too soon and a made-up token are answered as a success, store nothing and log the measure" do
    [ [ { website: "https://spam.example" }, "honeypot" ],
      [ { drawn: Forms::Drawn.token(@form) }, "too_soon" ],
      [ { drawn: "made-up" }, "invalid_token" ] ].each do |extra, measure|
      clear_form_send_limits # two sends a measure: six from one address in all
      log = nil
      assert_nothing_written do
        log = capture_log { send_form(**extra) }
      end
      assert_response :ok
      assert_select "[role=status]", text: "Thank you, we'll be in touch."
      assert_includes log, "[ContentSpiel] A form's send was dropped as spam: form #{@form.id}, #{measure}."

      send_form(json: true, **extra)
      assert_equal({ "status" => "sent", "message" => "Thank you, we'll be in touch." }, answer)
    end
  end

  test "the request's logged parameters hold no answer" do
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      send_form
      send_form(answers: ANSWERS.merge("f_mail0001" => "not-an-address"))
    end

    assert_includes log, "Processing by FormSendsController#create"
    assert_includes log, "[FILTERED]"
    [ *ANSWERS.values, "not-an-address" ].each { |typed| assert_not_includes log, typed }
  end

  test "no span of a send holds an answer" do
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    send_form
    send_form(answers: ANSWERS.merge("f_mail0001" => "not-an-address"), json: true)

    spans = exporter.finished_spans
    assert spans.any? { |span| span.kind == :server }, "the request's span is recorded: #{spans.map(&:name)}"
    text = spans.map { |span| [ span.name, span.attributes.to_a, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ") }.join("\n")
    [ *ANSWERS.values, "not-an-address" ].each { |typed| assert_not_includes text, typed }
  end

  test "the received event has no IP" do
    post form_send_path(@form), params: { answers: ANSWERS, locale: "en", page_id: @page.id, drawn: aged_drawn(@form) }, env: { "REMOTE_ADDR" => "203.0.113.9" }

    event = Audit::Event.where(action: "form_submission.received").order(:id).last
    assert event, "a received event was recorded"
    assert_nil event.ip
    assert_nil event.actor_id
    assert_equal "visitor", event.actor_label
    assert_equal "public", event.channel
    assert_not_includes event.attributes.to_json, "203.0.113.9"
  end

  test "the page drawn under a theme is not the theme's: none of its templates or its stylesheet" do
    with_plain_theme do
      get "/contact-us"
      assert_match(/plain-frame|plain-page/, response.body, "the control: the theme draws the public page")

      send_form
      assert_response :ok
      assert_no_match(/plain-frame|plain-mark|plain-page/, response.body)
      assert_select "link[rel=stylesheet][href*='/assets/tailwind']", count: 1
      assert_select "link[rel=stylesheet][href*='/assets/theme']", count: 0

      send_form(answers: ANSWERS.merge("f_name0001" => ""))
      assert_response :unprocessable_content
      assert_no_match(/plain-frame|plain-mark|plain-page/, response.body)
      assert_select "link[rel=stylesheet][href*='/assets/theme']", count: 0
    end
  end

  test "a signed-in editor's cookies are neither changed nor dropped by a send" do
    sign_in_as users(:one)
    get "/cs-studio"
    assert_response :success
    before = cookies.to_hash
    assert before.any?, "signed in with a cookie"

    send_form
    assert_response :ok
    assert_nil response.headers["Set-Cookie"]
    assert_equal before, cookies.to_hash

    send_form(answers: ANSWERS.merge("f_name0001" => ""), json: true)
    assert_nil response.headers["Set-Cookie"]
    assert_equal before, cookies.to_hash

    get "/cs-studio"
    assert_response :success
  end

  test "only a POST reaches it, and a send needs no token with forgery protection on" do
    get "/forms/#{@form.id}"
    assert_response :not_found
    assert_equal "PagesController", controller.class.name

    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_difference -> { Forms::Submission.count }, 1 do
      send_form
    end
    assert_response :ok
  ensure
    ActionController::Base.allow_forgery_protection = before
  end
end
