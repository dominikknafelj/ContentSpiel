module SiteSearch
  # The rate limit on searches (search spec §8.3), of `PagesController` and
  # `PreviewController`:
  #
  # - 20 searches per visitor in a minute: a person types a few, and pages
  #   through a few more;
  # - 600 searches in a minute across the site, the flood limit. Its cost,
  #   named: during a flood a real search is refused with the rest.
  #
  # ONLY A SEARCH COUNTS: a request whose `q` is a String with words left
  # once normalised (`PublicPageRendering#search_requested?`). A page view is never counted,
  # and neither is a `q` that is an Array or a Hash, or holds no words.
  #
  # ANY PAGE WITH `q` COUNTS, one without a Search block too: the limit is
  # decided before the page's blocks are read, as the no-store answer is.
  # Its cost, named: a link or a crawler that adds `q` to pages with no
  # search spends the visitor's twenty all the same.
  #
  # OVER EITHER, NOTHING HALTS: `with:` marks the request, the page is drawn
  # with status 429 and its Search block in `:limited`, and no backend is
  # asked (`SiteSearch::Answer.for` decides `:limited` first). A visitor who
  # is refused sees the page they asked for and why.
  #
  # ONE COUNT FOR BOTH DOORS: both limits name `scope: SCOPE`, where Rails'
  # default is the controller's path, so an editor's searches in the preview
  # count in the visitors' counters, with no exemption.
  #
  # THE VISITOR IS NOT AN ADDRESS IN THE CACHE: the key is
  # `VisitorAddress.key` under KEY_PURPOSE, an HMAC of the address keyed
  # from `secret_key_base`, so the store (Solid Cache, a table of the
  # database) holds no IP for its minute. An IPv6 visitor is their /64, an
  # IPv4 one the full address (`VisitorAddress` says why). Nothing of the
  # query is in a key or a value.
  #
  # WHO THE VISITOR IS rests on `request.remote_ip`, which is right only
  # behind proxies Rails trusts: Rails skips private and loopback hops in
  # `X-Forwarded-For`, so kamal-proxy on the same host is fine as it is. A
  # CDN in front (Cloudflare, which `config/deploy.yml` plans for) is a
  # public address Rails does not trust: every visitor then arrives "from"
  # the CDN's edge, shares one counter, and the 21st search of a minute
  # across the whole site is refused. Such a site sets TRUSTED_PROXIES to
  # the CDN's published ranges (lib/trusted_proxies.rb). Nothing here
  # detects the mistake; System status's "Visitor address" row does behind
  # Cloudflare. The site's limit is unaffected by it.
  #
  # THE STORE is `CounterStore.current`, the one every counter of the site
  # shares (it says why a test has a memory store).
  module QueryLimit
    extend ActiveSupport::Concern

    VISITOR_LIMIT = 20
    SITE_LIMIT = 600
    WITHIN = 1.minute
    KEY_PURPOSE = "content_spiel search visitor".freeze
    SCOPE = "site_search".freeze

    def self.store = CounterStore.current

    included do
      rate_limit to: VISITOR_LIMIT, within: WITHIN, name: "search_visitor", scope: SCOPE, store: QueryLimit.store,
        by: -> { VisitorAddress.key(request.remote_ip, purpose: KEY_PURPOSE) }, with: -> { @search_limited = true },
        if: -> { search_requested? }
      rate_limit to: SITE_LIMIT, within: WITHIN, name: "search_site", scope: SCOPE, store: QueryLimit.store,
        by: -> { "site" }, with: -> { @search_limited = true }, if: -> { search_requested? }
    end
  end
end
