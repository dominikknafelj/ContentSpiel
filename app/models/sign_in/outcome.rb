module SignIn
  # What one sign-in attempt came to (`SignIn::PasswordAttempt#call`), or
  # one second proof (`SignIn::Proof`).
  #
  #   status         one of SignIn::OUTCOMES
  #   account        the account proved, on `:ok` and
  #                  `:second_factor_required` only
  #   trips          `Throttle::Trip`s: on `:refused`, every bucket this
  #                  attempt closed (the account's first), which began with
  #                  it and so are audited and mailed once; on `:locked`,
  #                  the one closed bucket that refused it; otherwise none
  #   bot_check_due  whether the next attempt must carry the bot check
  Outcome = Data.define(:status, :account, :trips, :bot_check_due) do
    def ok? = status == :ok
  end
end
