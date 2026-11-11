module Forms
  # The rate limit on a visitor's sends, per visitor and per form, the
  # third measure beside the honeypot and the draw time (`Forms::SpamCheck`):
  #
  # - 5 sends per visitor in ten minutes, across every form: a person sends
  #   a contact form once or twice;
  # - 30 sends per form in ten minutes, from anyone: a small site's form gets
  #   a few a day, and 30 in ten minutes is a flood. Its cost, named: during
  #   a flood a real send is refused with the rest.
  #
  # Every send counts, a spam trip and a refused one too (Rails' `rate_limit`
  # counts before the action runs).
  #
  # SAID TO THE VISITOR: a send over either
  # is answered 429 with "Too many messages. Please try again in a few
  # minutes." (`public.forms.rate_limited`), as JSON `rate_limited` to the
  # script and as a plain page without it, and is stored nowhere. The
  # includer answers it: `answer_rate_limited`. It is not answered as a
  # success, as a honeypot is: a person who is refused must be told, or
  # they think their message went.
  #
  # THE VISITOR IS NOT AN ADDRESS IN THE CACHE: the key is
  # `VisitorAddress.key` under KEY_PURPOSE, an HMAC of the address keyed
  # from `secret_key_base`, so the store (Solid Cache, a table of the
  # database) holds no IP for its ten minutes. An IPv6 visitor is their /64,
  # an IPv4 one the full address (`VisitorAddress` says why).
  # The form's key is its id as a number: the route takes `/forms/007` as
  # form 7, and keying on the text as sent would give each spelling with
  # leading zeros a counter of its own.
  #
  # WHO THE VISITOR IS rests on `request.remote_ip`, which is right only
  # behind proxies Rails trusts: Rails skips private and loopback hops in
  # `X-Forwarded-For`, so kamal-proxy on the same host is fine as it is. A
  # CDN in front (Cloudflare, which `config/deploy.yml` plans for) is a
  # public address Rails does not trust: every visitor then arrives "from"
  # the CDN's edge, shares one counter, and the sixth visitor of ten minutes
  # is refused. Such a site sets TRUSTED_PROXIES to the CDN's published
  # ranges (lib/trusted_proxies.rb). Nothing here detects the mistake;
  # System status's "Visitor address" row does behind Cloudflare. The
  # per-form limit is unaffected by it.
  #
  # THE STORE is `CounterStore.current`, the one every counter of the site
  # shares (it says why a test has a memory store).
  module SendLimit
    extend ActiveSupport::Concern

    VISITOR_LIMIT = 5
    FORM_LIMIT = 30
    WITHIN = 10.minutes
    KEY_PURPOSE = "content_spiel form send visitor".freeze

    def self.store = CounterStore.current

    included do
      rate_limit to: VISITOR_LIMIT, within: WITHIN, name: "form_send_visitor", store: SendLimit.store,
        by: -> { VisitorAddress.key(request.remote_ip, purpose: KEY_PURPOSE) }, with: -> { answer_rate_limited }
      rate_limit to: FORM_LIMIT, within: WITHIN, name: "form_send_form", store: SendLimit.store,
        by: -> { params[:form_id].to_i.to_s }, with: -> { answer_rate_limited }
    end
  end
end
