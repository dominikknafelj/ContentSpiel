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
  # IN FLIGHT, a third bound: at most `IN_FLIGHT` suggestions are answered at
  # once in a process (`SLOTS`, a semaphore shared by its threads), below
  # Puma's default of three threads, so a flood the two counters let through
  # (50 a second, each holding a thread and a connection up to
  # `SUGGEST_TIMEOUT`) can never take every thread from the pages and CS
  # Studio. A request that finds every slot taken is answered `limited` at
  # once, never queued; a slot is given back on every path, a raise
  # included (`in_a_slot`). It is per process and fixed, not read from
  # `RAILS_MAX_THREADS`: more threads leave more for the pages.
  #
  # OVER ANY of the three the includer answers `answer_limited` (429,
  # `limited`, the request span's `search.outcome`), and no backend is
  # asked.
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
    IN_FLIGHT = 2
    SLOTS = Concurrent::Semaphore.new(IN_FLIGHT)

    def self.store = CounterStore.current

    # Yields holding one of `SLOTS` and answers true, or answers false at
    # once, yielding nothing, when every slot is taken. The slot is given
    # back however the block ends.
    def self.in_a_slot
      return false unless SLOTS.try_acquire

      begin
        yield
      ensure
        SLOTS.release
      end
      true
    end

    included do
      rate_limit to: VISITOR_LIMIT, within: WITHIN, name: "suggest_visitor", scope: SCOPE, store: SuggestLimit.store,
        by: -> { VisitorAddress.key(request.remote_ip, purpose: QueryLimit::KEY_PURPOSE) }, with: -> { answer_limited }
      rate_limit to: SITE_LIMIT, within: WITHIN, name: "suggest_site", scope: SCOPE, store: SuggestLimit.store,
        by: -> { "site" }, with: -> { answer_limited }
      around_action :in_a_suggestion_slot
    end

    private

    def in_a_suggestion_slot(&action) = SuggestLimit.in_a_slot(&action) || answer_limited
  end
end
