module Users
  # A password a person sets is refused when it is in the list of leaked
  # passwords (`SignIn::LeakedPassword`), with the sentence
  # `activerecord.errors.models.user.attributes.password.leaked` on the
  # password, as the model's own rules are. The three services through which
  # a person sets one include it: `Users::Save`, `Users::UpdatePassword` and
  # `Invitations::Accept`. The seeds and the console write the model directly
  # and are not checked.
  #
  # WHEN IT IS ASKED. Only when the check is on, and then only once the
  # record is otherwise valid (`leaked_password?` runs `valid?` itself, after
  # the switch, so a save with the check off validates once): a blank, short
  # or unconfirmed password is refused by the model first, so it never leaves
  # the process. And before the service's transaction: the lookup is an
  # outside call of up to five seconds, which must not hold a row lock that
  # other requests wait on.
  #
  # FAILING OPEN. Only `:leaked` refuses. `:unavailable` (the service could
  # not be asked; `SignIn::LeakedPassword` writes the line) and `:off` (the
  # switch, off by default outside production) accept the password, and the
  # save says nothing of the check.
  module LeakedPasswordRule
    private

    # Whether `password`, being set on `record`, is leaked. Asks nothing when
    # the check is off or `record` is otherwise invalid; a caller with a rule
    # of its own beyond the model's (an unconfirmed password) refuses first.
    def leaked_password?(record, password)
      SignIn::LeakedPassword.on? && record.valid? && SignIn::LeakedPassword.check(password) == :leaked
    end

    def leaked_password_failure(record)
      record.errors.add(:password, :leaked)
      failure(record)
    end
  end
end
