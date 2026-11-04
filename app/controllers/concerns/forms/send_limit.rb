module Forms
  # The rate limit on a visitor's sends (forms spec, "Spam measures": "a rate
  # limit per visitor and per form"; plan decision 5), the third measure
  # beside the honeypot and the draw time (`Forms::SpamCheck`):
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
  # SAID TO THE VISITOR (owner's ruling 1, pre-flight R1): a send over either
  # is answered 429 with "Too many messages. Please try again in a few
  # minutes." (`public.forms.rate_limited`), as JSON `rate_limited` to the
  # script and as a plain page without it, and is stored nowhere. The
  # includer answers it: `answer_rate_limited`. (The plan had it answered as
  # a success, as a honeypot is; a person who is refused must be told, or
  # they think their message went.)
  #
  # THE VISITOR IS NOT AN ADDRESS IN THE CACHE: the key is an HMAC of the
  # address (`visitor_key`), keyed from `secret_key_base`, so the store
  # (Solid Cache, a table of the database) holds no IP for its ten minutes.
  # The form's key is its id.
  #
  # THE STORE follows `MailTestLimit.store`'s rule: `Rails.cache`, unless it
  # is a `NullStore` (the test environment's), whose every write is a no-op
  # and whose limit could never trip; there it is one memory store of the
  # process (`store`, which a test clears). Captured when the class is
  # defined.
  module SendLimit
    extend ActiveSupport::Concern

    VISITOR_LIMIT = 5
    FORM_LIMIT = 30
    WITHIN = 10.minutes
    KEY_PURPOSE = "content_spiel form send visitor".freeze

    def self.store
      @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
    end

    # The visitor as the cache knows them: a hex HMAC-SHA256 of the address.
    def self.visitor_key(ip)
      @key ||= Rails.application.key_generator.generate_key(KEY_PURPOSE)
      OpenSSL::HMAC.hexdigest("SHA256", @key, ip.to_s)
    end

    included do
      rate_limit to: VISITOR_LIMIT, within: WITHIN, name: "form_send_visitor", store: SendLimit.store,
        by: -> { Forms::SendLimit.visitor_key(request.remote_ip) }, with: -> { answer_rate_limited }
      rate_limit to: FORM_LIMIT, within: WITHIN, name: "form_send_form", store: SendLimit.store,
        by: -> { params[:form_id].to_s }, with: -> { answer_rate_limited }
    end
  end
end
