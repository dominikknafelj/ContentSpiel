module SiteSearch
  # The rate limit on the suggestions while typing (search 2 spec §4.2), of
  # `SiteSearch::SuggestionsController`:
  #
  # - 120 a minute per visitor: the script waits after the last keystroke
  #   and asks from two characters, so a query costs a few requests, and a
  #   person who searches ten times in a minute stays near 60;
  # - 3,000 a minute across the site, the flood limit. Its cost, named:
  #   during a flood a real visitor's suggestions are refused with the rest,
  #   and the form still sends.
  #
  # COUNTERS OF THEIR OWN (`suggest_visitor`, `suggest_site`, under
  # `SCOPE`), never the search's (`QueryLimit`): typing two queries would
  # otherwise spend a visitor's twenty searches, and the search they then
  # send would be refused. The visitor key is the search's own
  # (`VisitorAddress.key` under `QueryLimit::KEY_PURPOSE`), an HMAC of the
  # address, so the store holds no IP; nothing of the prefix is in a key or
  # a value.
  #
  # ONLY A REQUEST THE CHECKS LET THROUGH COUNTS: the includer includes this
  # after its refusals (another site's, a body that is not the endpoint's),
  # whose answer halts the chain before Rails' `rate_limit` counts. A body
  # too large never reaches the controller (`ContentSpiel::SuggestGate`).
  #
  # OVER EITHER the includer answers `answer_limited` (429, `limited`), and
  # no backend is asked.
  #
  # WHO THE VISITOR IS rests on `request.remote_ip`, as for the search's
  # limit (`QueryLimit` says what a CDN in front needs). THE STORE is
  # `CounterStore.current`.
  module SuggestLimit
    extend ActiveSupport::Concern

    VISITOR_LIMIT = 120
    SITE_LIMIT = 3_000
    WITHIN = 1.minute
    SCOPE = "site_search_suggest".freeze

    def self.store = CounterStore.current

    included do
      rate_limit to: VISITOR_LIMIT, within: WITHIN, name: "suggest_visitor", scope: SCOPE, store: SuggestLimit.store,
        by: -> { VisitorAddress.key(request.remote_ip, purpose: QueryLimit::KEY_PURPOSE) }, with: -> { answer_limited }
      rate_limit to: SITE_LIMIT, within: WITHIN, name: "suggest_site", scope: SCOPE, store: SuggestLimit.store,
        by: -> { "site" }, with: -> { answer_limited }
    end
  end
end
