# The suggestions while typing (search 2 spec §4.1, §4.2): `POST
# /search/suggestions` with the JSON body `{"suggest": "<prefix>",
# "language": "de"}`, answered with JSON the Search block's script draws:
#
#   ok           200  { "state": "ok", "status", "suggestions": [{ "kind", "kind_label", "label", "where", "url", "marks" }] }
#   unavailable  200  { "state": "unavailable", "status", "suggestions": [] }   the backend failed or was late
#   limited      429  { "state": "limited", "status", "suggestions": [] }       over a limit (`SiteSearch::SuggestLimit`)
#   refused      403  { "state": "refused", "status": "", "suggestions": [] }    another site's browser, or not JSON
#   refused      400  the same                                                   a body that is not the endpoint's
#   refused      413  the same, answered by `ContentSpiel::SuggestGate`          a body over 1 KB
#
# `status` is the one sentence a screen reader hears, in the language
# asked; `kind_label`, `label`, `where` and `url` are plain text, with `<`,
# `>` and `&` escaped in the JSON (`answer_with`); `marks` are `[start, length]` ranges on `label`
# (`SiteSearch::SuggestAnswer`). The answer depends on no page: the path
# names no language and no page is resolved.
#
# NOT A `PublicController`, as `FormSendsController` is not: never cached,
# no theme. But it keeps the public wall, `Cookieless`, FIRST: no session is
# read or committed, no token is minted, no `Set-Cookie` leaves.
#
# NO CSRF TOKEN, AND WHY THAT IS SAFE. A public page carries none. What
# forgery protection guards is a signed-in person's power, a forged request
# that rides their cookies; this request reads no session, runs as no one,
# writes nothing and answers only what the public site shows. Its one side
# effect is a count in the limits, which another site's pages could spend
# with their visitors' browsers, so such a request is refused, with 403,
# nothing asked and nothing counted (`refuse_cross_site`). A request with
# neither header (curl, a script) is answered: it could write either header
# anyway, and the limits bound it as they bound a crawler's `?q=`.
#
# THE PREFIX IS PERSONAL DATA, as a search's query is: the body is capped
# and parsed by the gate, which hands Rails none of it (no "Parameters:"
# line, no parse error that could quote it; `suggest` is in
# `filter_parameters` all the same), the spans carry no prefix (`SiteSearch.suggest`; a refusal is the
# request span's `search.outcome`), and nothing here logs, stores or
# reports it. The controller reads the gate's parsed body and never
# `params`. A POST keeps it out of the front servers' access logs too.
class SiteSearch::SuggestionsController < ActionController::Base
  include Cookieless

  # The token is not checked here, by design (above). `Cookieless` already
  # answers `protect_against_forgery?` false; this says so where Rails looks.
  skip_forgery_protection

  # The body is the gate's (`ContentSpiel::SuggestGate`) and Rails parses
  # none of it, so there is nothing to wrap under the controller's name.
  wrap_parameters false

  # In this order, ahead of the limit: a refusal answers no-store, halts and
  # counts nothing.
  before_action :answer_privately
  before_action :refuse_cross_site
  before_action :refuse_malformed

  include SiteSearch::SuggestLimit

  STATUSES = { ok: :ok, unavailable: :ok, limited: :too_many_requests }.freeze

  def create
    answer = SiteSearch.suggest(text: body.fetch("suggest"), language: language, now: Time.current)
    answer_with(payload(answer.state, answer.items), STATUSES.fetch(answer.state))
  end

  private

  # The visitor's own answer: no cache keeps it (no-store, and no ETag:
  # nothing here asks `stale?`), and no search engine indexes it.
  def answer_privately
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("X-Robots-Tag", "noindex")
  end

  # Another site's browser: `Sec-Fetch-Site` present and not `same-origin`;
  # else `Origin` present and not this request's own (`request.base_url`,
  # which `HostSettings` holds to `PUBLIC_HOST`). And any request whose type
  # is not `application/json`: a cross-site `fetch` of that type needs a
  # CORS preflight, which nothing here answers, so only a "simple" POST
  # (form data, `text/plain`) could come from another site, and it is
  # refused here.
  def refuse_cross_site
    fetch_site = request.headers["Sec-Fetch-Site"].presence
    origin = request.headers["Origin"].presence
    other = fetch_site ? fetch_site != "same-origin" : (origin && origin != request.base_url)
    refuse(:forbidden) if other || request.media_type != "application/json"
  end

  # A body that did not parse (`ContentSpiel::SuggestGate`'s flag), that is
  # no JSON object, or whose `suggest` is missing or no String.
  def refuse_malformed
    refuse(:bad_request) unless body.is_a?(Hash) && body["suggest"].is_a?(String)
  end

  # The body as the gate parsed it. A request the gate did not read has
  # none, and is malformed.
  def body = request.get_header(ContentSpiel::SuggestGate::ENV_KEY)

  # The body's `language` when it is a switched-on language, else the site's
  # default, so `SiteSearch.suggest` is never handed a language the site
  # does not have.
  def language
    @language ||= body["language"].is_a?(String) && Locales.enabled?(body["language"]) ? body["language"] : Locales.default
  end

  def refuse(status)
    record_outcome("refused")
    answer_with({ state: "refused", status: "", suggestions: [] }, status)
  end

  # Over a limit (`SiteSearch::SuggestLimit`): nothing is asked.
  def answer_limited
    record_outcome("limited")
    answer_with(payload(:limited, []), STATUSES.fetch(:limited))
  end

  # The JSON encoded with `<`, `>` and `&` escaped (`\u003c` and the
  # others), so a title or a tag that looks like markup is no markup even
  # to a reader that takes the answer for HTML. `render json:` with an
  # object skips that escape under this version's defaults
  # (`escape_json_responses`), so it is handed the encoded String.
  def answer_with(json, status)
    render json: ActiveSupport::JSON.encode(json), status: status
  end

  # A request answered without a suggestion's span: its outcome is on the
  # request's own (search 2 spec §9.1), never on `search.suggest`.
  def record_outcome(outcome) = Telemetry.record(OpenTelemetry::Trace.current_span, "search.outcome" => outcome)

  def payload(state, items)
    {
      state: state.to_s,
      status: status_of(state, items.size),
      suggestions: items.map do |item|
        { kind: item.kind.to_s, kind_label: word(:"kind_#{item.kind}"), label: item.label, where: item.where, url: item.url, marks: item.marks }
      end
    }
  end

  def status_of(state, count)
    case state
    when :limited then word(:suggestions_limited)
    when :unavailable then word(:suggestions_unavailable)
    else count.zero? ? word(:no_suggestions) : word(:suggestions, count: count)
    end
  end

  def word(key, **options) = PublicStrings.read("public.blocks.search.#{key}", locale: language, **options)
end
