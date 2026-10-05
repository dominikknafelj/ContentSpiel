module Users
  # Rules every user-changing service shares (access-control design spec
  # §3.3 "Users"):
  #
  # - Owner accounts are owner-only. `users.manage` covers other users, but
  #   not an owner's: a non-owner who could change an owner's email or
  #   password could simply sign in as them, which would make the owner
  #   flag -- the one privilege no group can grant -- worth no more than
  #   `users.manage`. So only an owner may edit, reset or delete an owner
  #   (Review Focus 1, no privilege escalation).
  # - A non-owner manages another user only if that user's rights are a
  #   subset of their own (`#outranked?`, fix round 1).
  # - A password change never reaches the log: `password_digest` is
  #   scrubbed from every snapshot and changes hash (Review Focus 5), so
  #   `user_field_changes` records that it changed as `"credentials"`
  #   instead -- a key no `filter_parameters` entry matches, with no value
  #   derived from the password.
  # - A password change ends that user's sessions
  #   (`#end_sessions_after_password_change`), in the transaction that
  #   writes the password -- here rather than in a controller, so no path
  #   to a new password can forget it.
  module OwnerProtection
    private

    # The predicates live in `Users::Manageability` (round 3 Task 12), which the
    # user editor asks too, so what the screen shows and what these services
    # refuse can't drift. They are read at call time with the service's own
    # actor and `Current.channel`, as they always were.
    def owner_protected? = Manageability.owner_protected?(actor, @user)

    # An owner, or a trusted code path; never an API token (see Manageability).
    def actor_owner? = Manageability.actor_owner?(actor)

    # A non-owner may only manage users whose groups they could manage as they
    # stand (fix round 1, I1); see Manageability#outranked?.
    def outranked? = Manageability.outranked?(actor, @user)

    def owner_only_denial
      denied("users.manage", @user, message: "You don't have permission to change an owner's account")
    end

    # Someone changes a password because the old one is, or may be, in the
    # wrong hands -- and whoever holds it may already be signed in, so a new
    # password that left the old sessions alive would lock nobody out. Every
    # session of the user is destroyed, called inside the saving transaction
    # right after the save: a rolled-back change ends none, and a committed
    # one never leaves a window with the new password and the old sessions.
    #
    # The one session kept is the one the change is being made *in*, when a
    # signed-in user changes their own password (`keep_acting_session`,
    # which the reset flow turns off -- there the emailed token made the
    # change, not a session, and a reset is what someone does who has lost
    # the account). It is only ever a session of this very user: an admin
    # changing someone else's password keeps their own session simply
    # because it isn't among that user's, and an API token has no session.
    #
    # Only a *changed* digest counts -- a blank password field, a new name or
    # new groups touch no session -- and a user being created has none.
    def end_sessions_after_password_change(keep_acting_session: true)
      return unless @user.saved_change_to_password_digest? && !@user.previously_new_record?

      sessions = @user.sessions
      kept = Current.session if keep_acting_session && actor.is_a?(User) && actor == @user
      sessions = sessions.where.not(id: kept.id) if kept && kept.user_id == @user.id
      sessions.destroy_all
    end

    def user_field_changes(user)
      changes = Audit::Snapshot.field_changes_for(user)
      changes["credentials"] = [ nil, "password changed" ] if user.saved_change_to_password_digest? && !user.previously_new_record?
      changes
    end
  end
end
