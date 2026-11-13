module SignIn
  module Sso
    # Who the provider says signed in: its issuer and subject (the pair an
    # account is linked by), the email and whether the provider verified it,
    # the name, and the refresh token it gave, if any.
    #
    # `inspect`, `to_s` and `as_json` leave out the refresh token, a secret,
    # and the email, which reaches no log line or span: an error page or a
    # log of the object shows the issuer and subject alone.
    Identity = Data.define(:issuer, :subject, :email, :email_verified, :name, :refresh_token) do
      def inspect = "#<#{self.class.name} issuer=#{issuer.inspect} subject=#{subject.inspect}>"
      alias_method :to_s, :inspect

      def as_json(*) = { "issuer" => issuer, "subject" => subject }

      def issuer_host = SignIn::Sso.issuer_host(issuer)
    end
  end
end
