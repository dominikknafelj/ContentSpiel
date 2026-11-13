module SignIn
  module Sso
    # The one writer of `sso.linked`, included by the two services that link an
    # account: `SignIn::Sso::Link` (an existing account matched by its verified email,
    # `via: "sign_in"`) and `Invitations::AcceptWithSso` (an account made linked
    # from an invitation, `via: "invitation"`, with nothing to remove), so the
    # event never has two shapes.
    #
    # Why AcceptWithSso does not call `SignIn::Sso::Link`: Link rewrites the password
    # through `Users::UpdatePassword` (a second `user.updated` for an account made
    # a moment before, already with a password nobody holds), and it rescues the
    # unique index's refusal after its own transaction, which inside the
    # acceptance's is no savepoint: Postgres has aborted the outer transaction by
    # then, so Link's `reload` would raise in place of the `[:used]` the
    # acceptance answers.
    #
    # Called inside the includer's transaction, with the account as the actor.
    module LinkedEvent
      VIA = %w[sign_in invitation].freeze

      private

      def record_linked(user, identity:, via:, passkeys_removed: 0, recovery_codes_removed: 0)
        raise ArgumentError, "via is one of #{VIA.join(", ")}, not #{via.inspect}" unless VIA.include?(via)

        record_event("sso.linked", subject: user, snapshot: nil, metadata: {
          "via" => via, "issuer_host" => identity.issuer_host, "passkeys_removed" => passkeys_removed, "recovery_codes_removed" => recovery_codes_removed
        })
      end
    end
  end
end
