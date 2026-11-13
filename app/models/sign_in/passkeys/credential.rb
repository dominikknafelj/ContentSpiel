module SignIn
  module Passkeys
    # What a browser sent as a passkey's answer, read before the webauthn gem
    # sees it. The text comes from anyone who can reach a sign-in form, and
    # the gem trusts the shape it is handed: given a hash with no `rawId` or a
    # `response` that is a String it raises NoMethodError, and given a `type`
    # or an `id` it dislikes it raises a bare RuntimeError, neither of which a
    # caller can tell from a bug. So the shape is checked here (`parse`), and
    # what the gem still raises over well-shaped bytes (truncated authenticator
    # data, CBOR that is not an attestation, a signature OpenSSL can't read) is
    # the closed list MALFORMED. Each is refused as a wrong passkey, never a
    # 500.
    #
    # A text over MAX_CREDENTIAL_BYTES is refused before it is parsed: a real
    # credential is a few hundred bytes to a few kilobytes (a credential id is
    # at most 1,023 bytes, a key a few hundred), and parsing a large text is
    # work an anonymous caller should not be able to buy.
    module Credential
      MAX_CREDENTIAL_BYTES = 16_384

      MALFORMED = [
        WebAuthn::Error, JSON::ParserError, KeyError, ArgumentError, TypeError,
        CBOR::UnpackError, EOFError, IOError, OpenSSL::PKey::PKeyError, COSE::Error
      ].freeze

      TYPE = "public-key".freeze

      # The credential as a Hash the gem can read without raising on its
      # shape, or nil. `fields` are the response's members that must be
      # Strings (`attestationObject` for a registration; `authenticatorData`
      # and `signature` for an assertion; `clientDataJSON` always); `userHandle`
      # may be a String or absent, `transports` an Array of Strings or absent.
      def self.parse(text, fields:)
        return nil unless text.is_a?(String) && text.bytesize <= MAX_CREDENTIAL_BYTES

        credential = JSON.parse(text)
        return nil unless credential.is_a?(Hash) && credential["type"] == TYPE
        # The gem compares `id` with `rawId` decoded; both are base64url here,
        # so the two texts are the same text.
        return nil unless credential["id"].is_a?(String) && credential["id"].present? && credential["rawId"] == credential["id"]
        return nil unless optional?(credential["clientExtensionResults"], Hash) && optional?(credential["authenticatorAttachment"], String)

        response = credential["response"]
        return nil unless response.is_a?(Hash) && [ "clientDataJSON", *fields ].all? { |field| response[field].is_a?(String) }
        return nil unless optional?(response["userHandle"], String)
        return nil unless response["transports"].nil? || (response["transports"].is_a?(Array) && response["transports"].all?(String))
        return nil unless client_data?(response["clientDataJSON"])

        credential
      rescue JSON::ParserError, ArgumentError
        nil
      end

      # The client data the gem reads `type`, `challenge` and `origin` from,
      # each with a String method: a JSON object whose three are Strings.
      def self.client_data?(encoded)
        data = JSON.parse(WebAuthn.standard_encoder.decode(encoded))
        data.is_a?(Hash) && %w[type challenge origin].all? { |key| data[key].is_a?(String) }
      end

      def self.optional?(value, type) = value.nil? || value.is_a?(type)
      private_class_method :client_data?, :optional?
    end
  end
end
