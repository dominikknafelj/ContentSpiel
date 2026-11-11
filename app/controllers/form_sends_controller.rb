# The endpoint a visitor's form posts to: `POST /forms/:form_id`. The
# form posts here, never to its page, so a public page stays a GET that is
# the same cookie-less answer for everyone, and its ETag and caching are
# untouched.
#
# NOT A `PublicController`. It is never cached (`Cache-Control: no-store` on
# every answer, a refusal included), it draws no theme (the theme's views
# are on the two public controllers' path only, `PublicPageRendering`), and
# its plain pages are the CMS's own, in a layout of their own
# (`layouts/form_send`: no CSRF tag, no script of CS Studio,
# the visitor's language, no sign-in link). But it keeps the public wall,
# `Cookieless`, first: no session is committed, no token is minted and no
# `Set-Cookie` leaves, so a signed-in editor who sends a form on their own
# site keeps their cookies as they are.
#
# NO CSRF TOKEN, AND WHY THAT IS SAFE (`docs/reference/forms.md` keeps the
# same reason). A public page
# carries no token (it would need a session, and the page would no longer
# be the same for everyone), so a send cannot be checked for one. What
# forgery protects is a signed-in person's power: a forged request that
# rides their cookies. A send has none to ride: it runs as the visitor
# (`AccessControl::VISITOR`, allowed `forms.submit` on `:public` and
# nothing else), reads no session, and can do nothing but be a submission,
# the same submission anybody could send from the page itself. A forged
# send is therefore just a send, and is met by the spam measures as every
# send is: the honeypot and the signed draw time (`Forms::SpamCheck`), and
# the rate limit per visitor and per form (`Forms::SendLimit`).
#
# WHAT IT ANSWERS, by `Accept`: JSON to the Form block's script, which
# writes the words in place, and otherwise a plain page of the same
# status, each with a link back to the page the form came from:
#
#   sent          200  { "status": "sent", "message" }        the form's thank-you, else `public.forms.sent`
#   invalid       422  { "status": "invalid", "summary", "errors": [{ "key", "message", "item" }] }
#   gone          404  { "status": "gone", "message" }        no such form, one that takes no sends (below), or in the trash
#   rate_limited  429  { "status": "rate_limited", "message" } over a rate limit, told, never answered as sent
#   unavailable   503  { "status": "unavailable", "message" }  no encryption keys
#
# An error's `item` is its summary link's words, "<label>: <message>"
# (`public.forms.error_item`, so a language orders the two parts), written
# here because the script holds no words of its own.
#
# Every status is its own word, so the script tells a success, field errors,
# a refusal and a failure of the network (no answer at all)
# apart. A spam trip is answered exactly as `sent`, stores nothing and
# records no event (`Forms::SpamCheck`), with one log line naming the form
# and the measure.
#
# PERSONAL DATA: the answers arrive as
# `answers[<field key>]` and are filtered from the request's log by where
# they arrive (`config/initializers/filter_parameter_logging.rb`, which
# names this controller's path, `form_sends`); spans carry no body and no
# query string (`Telemetry::PathScrubber`); nothing of them is in a URL.
# THE VISITOR'S ADDRESS: `Current.ip_address` is never set here, so the
# visitor's event has no IP (`Audit.record`); the rate limit's cache key is
# an HMAC of it (`VisitorAddress.key`); no span of ours names it.
# Rails' own request line ("Started POST "/forms/1" for <address> at …")
# still does, as for every request of the site: that is the request log's,
# not this endpoint's, and it holds no answer.
#
# A FORM TAKES A SEND ONLY FROM A LIVE PAGE THAT PLACES IT (the owner's
# rule, 2026-11-05): it must have a field a visitor is drawn
# (`Forms::Form#drawn_fields`), and the page the send names (`page_id`, the
# visitor's to name) must be a live page whose published copy places this
# form (`Forms::Placements.live_page`). A form that fails either, a form
# being built and placed nowhere, one placed only on a draft or a trashed
# page, one with no fields, is NO FORM to this endpoint: `form_record` is
# nil for it, so it is answered exactly as an unknown id is (`gone`, 404,
# the link back to the site's home), ahead of the spam measures, and stores,
# mails and records nothing. It counts in the rate limits as an unknown id
# does, since they run before the action and key on the id as sent. A probe
# of the sequential ids therefore learns nothing it could not learn from the
# public pages, and every submission is made with its page (`page_id` goes
# nil later only when that page is purged). Its cost: a send from `/preview`
# of a draft page, or of a form not yet published on its page, is refused.
class FormSendsController < ActionController::Base
  include Cookieless

  # The token is not checked here, by design (above). `Cookieless` already
  # answers `protect_against_forgery?` false; this says so where Rails looks.
  skip_forgery_protection

  layout "form_send"

  STATUSES = {
    sent: :ok, invalid: :unprocessable_content, gone: :not_found, rate_limited: :too_many_requests, unavailable: :service_unavailable
  }.freeze

  # Ahead of the rate limit, so a 429 is not cached and is drawn as a page.
  before_action :no_store
  before_action { request.format = :html unless json? }
  before_action :act_as_visitor

  include Forms::SendLimit

  helper_method :word, :locale, :back_path, :site_title, :thank_you, :submit_label, :form_record, :trusted_page,
    :public_fields, :checked, :drawn_token

  def create
    return answer(:gone) unless form_record

    if (measure = Forms::SpamCheck.call(params, form: form_record, now: Time.current))
      Rails.logger.info("[ContentSpiel] A form's send was dropped as spam: form #{form_record.id}, #{measure}.")
      return answer(:sent)
    end

    result = Forms::Submit.call(form_record, answers: answers_param, locale: locale, page: trusted_page)
    return answer(:sent) if result.ok?

    case result.errors.first
    when Forms::Submit::INVALID
      @checked = result.record
      answer(:invalid)
    when Forms::Submit::GONE then answer(:gone)
    else answer(:unavailable)
    end
  end

  private

  # A send over a rate limit is told so, not answered as sent
  # (`Forms::SendLimit`).
  def answer_rate_limited = answer(:rate_limited)

  def answer(kind)
    status = STATUSES.fetch(kind)
    return render(json: payload(kind), status: status) if json?

    render kind, status: status
  end

  def payload(kind)
    case kind
    when :sent then { status: "sent", message: thank_you }
    when :invalid
      errors = checked.errors.map do |key, error|
        field = field_for(key)
        message = field.error_text(error)
        { key: key, message: message, item: word(:error_item, label: field.label, message: message) }
      end
      { status: "invalid", summary: word(:error_summary, count: errors.size), errors: errors }
    else { status: kind.to_s, message: word(kind) }
    end
  end

  def json? = request.format.json?

  # The one actor of a send (test/lib/visitor_actor_test.rb: this is the
  # only file that names it). No `Current.ip_address`: a visitor's event
  # carries no IP (the request log's own line still does; see the head).
  def act_as_visitor
    Current.actor = AccessControl::VISITOR
    Current.channel = :public
    Current.request_id = request.request_id
  end

  # The form a send is for, or nil: no such id, or a form that takes no
  # sends (the head's rule), which is then answered as no such id is.
  # Found in the trash too: `Forms::Submit` answers a trashed form GONE under
  # the form's lock, and the page then still links back where it came from.
  def form_record
    return @form_record if defined?(@form_record)

    form = Forms::Form.find_by(id: params[:form_id])
    @trusted_page = form && form.drawn_fields.any? ? Forms::Placements.live_page(form, params[:page_id]) : nil
    @form_record = @trusted_page ? form : nil
  end

  # The language the visitor sent in, if the site has it on, else the default.
  def locale
    @locale ||= Locales.enabled?(params[:locale].to_s) ? params[:locale].to_s : Locales.default
  end

  # Only a Hash is answers; anything else is none (every field blank).
  def answers_param = params[:answers].is_a?(ActionController::Parameters) ? params[:answers] : {}

  # The live page the send came from, set with `form_record`: never nil for
  # a form this endpoint takes a send for.
  def trusted_page
    form_record
    @trusted_page
  end

  # The page's address in the visitor's language, else the site's home there.
  def back_path
    @back_path ||= (trusted_page && urls.path_for(trusted_page, locale)) || urls.prefix(locale).presence || "/"
  end

  # Addresses only, never absolute: the visitor is already on this host.
  def urls = @urls ||= PublicSite::Urls.new

  def word(key, **options) = PublicStrings.read("public.forms.#{key}", locale: locale, **options)

  def thank_you = form_record&.thank_you_in(locale).presence || word(:sent)

  def submit_label = form_record.submit_label_in(locale).presence || word(:submit)

  def site_title = Locales.read(Current.site, :title, locale: locale).presence

  # The cleaned answers of an invalid send (`Forms::Answers::Result`).
  attr_reader :checked

  # The form's fields as this page draws them. `place` names the ids: one
  # form on one page, so the place is the page's own word.
  def public_fields
    @public_fields ||= form_record.drawn_fields.map { |field| Forms::PublicField.new(field: field, locale: locale, form_id: form_record.id, place: "send") }
  end

  def field_for(key) = public_fields.find { |field| field.key == key }

  # The token the visitor SENT, never a fresh one: a correction sent within
  # three seconds of this page is not
  # too soon, because the clock started when the form was first drawn.
  def drawn_token = params[:drawn].is_a?(String) ? params[:drawn] : nil
end
