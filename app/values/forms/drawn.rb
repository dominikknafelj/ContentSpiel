module Forms
  # The signed draw time a Form block carries (forms plan, decision 10; the
  # spec's "minimum time between the page being drawn and the send, carried
  # in the form and signed so it cannot be faked"), without a session: the
  # page holds the token, the send hands it back.
  #
  #   Forms::Drawn.token(form)                # => "eyJ…--…", in the form's hidden `drawn`
  #   Forms::Drawn.check(token, form: form)   # => :ok | :too_soon | :invalid
  #
  # A message verifier of the application's secret (`secret_key_base`) with
  # a purpose of its own, over `{ "f" => form id, "t" => seconds }`: a token
  # of another form, of another purpose or changed by a byte is `:invalid`.
  #
  # NO EXPIRY, on purpose. A public page is cached (its ETag, a CDN), so the
  # token a visitor is handed may be hours or weeks old; that only makes it
  # older than the minimum, which is all it has to prove. A bot that keeps a
  # token and replays it is met by the rate limit (`Forms::SendLimit`), not
  # by this.
  #
  # The no-JavaScript error page hands back the token the visitor SENT, never
  # a fresh one (`form_sends/invalid`), or a correction sent within three
  # seconds of that page would be dropped as too fast (the plan's Review
  # Focus 1).
  module Drawn
    MIN_SECONDS = 3
    PURPOSE = "content_spiel forms drawn".freeze

    module_function

    def token(form, at: Time.current) = verifier.generate({ "f" => form.id, "t" => at.to_i })

    def check(token, form:, now: Time.current)
      data = token.is_a?(String) && token.present? ? verifier.verified(token) : nil
      return :invalid unless data.is_a?(Hash) && data["f"] == form.id && data["t"].is_a?(Integer)

      now.to_i - data["t"] >= MIN_SECONDS ? :ok : :too_soon
    rescue ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature
      :invalid
    end

    def verifier = Rails.application.message_verifier(PURPOSE)
  end
end
