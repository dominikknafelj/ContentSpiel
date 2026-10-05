module Users
  # May `actor` change `user`'s account? ONE answer, asked by every
  # user-changing service (`Users::OwnerProtection`, which delegates its
  # private predicates here) and by the user editor, which draws its read-only
  # states from it (round 3 Task 12, decision D17) -- so what the screen
  # offers and what the services enforce can't drift apart.
  #
  #   Users::Manageability.for(actor, user)
  #     :editable         -- nothing here stops the actor (the permission
  #                          `users.manage` itself is a separate question,
  #                          `AccessControl.allowed?`, asked by the module and
  #                          every service);
  #     :owner_protected  -- `user` is an owner and the actor isn't one: only an
  #                          owner may edit, reset or delete an owner
  #                          (Review Focus 1: a non-owner who could change an
  #                          owner's email or password could sign in as them);
  #     :outranked        -- `user` holds a group the actor may not manage as it
  #                          stands (`AccessControl.can_manage_group?`): the
  #                          actor may only manage users whose rights are a
  #                          subset of their own (fix round 1, I1).
  #
  # The two predicates are checked in that order, exactly as the services did
  # (a non-owner looking at an owner who also holds an outranking group gets
  # `:owner_protected`), and each is public so a service that needs only one
  # question asks it. A user being created is always `:editable`.
  #
  # THE VIEW DECIDES NOTHING HERE. The answer only chooses what is drawn (a
  # disabled form and a notice instead of a footer); every refusal stays in the
  # services, which ask again on the request itself, so a forged PATCH or
  # DELETE against a read-only user is refused (and logged as one
  # `access.denied`) whatever the page showed.
  #
  # Who counts as the actor, which the extraction kept exactly:
  # - an owner is a `User` with the flag, nothing else. An `ApiToken` is NEVER
  #   an owner, not even an owner's: it acts within its group and is judged on
  #   its effective rights (group and user) wherever an owner would be waved
  #   through (final fix wave, Minor 1);
  # - a nil actor is trusted on the trusted channels (`:setup`, `:console`,
  #   `:system`, or no channel at all) and counts as an owner there; on any
  #   other channel it is not an owner (and the services deny it before they
  #   get here);
  # - acting on yourself is never "outranked" (a token acting on its own user
  #   included). Yourself can't be `:owner_protected` either: an owner target
  #   is yourself only when you are the owner.
  module Manageability
    module_function

    # `channel:` is read from `Current` at call time, as the services always
    # did; the explicit keyword is for a caller that knows better.
    def for(actor, user, channel: Current.channel)
      return :owner_protected if owner_protected?(actor, user, channel: channel)
      return :outranked if outranked?(actor, user, channel: channel)

      :editable
    end

    def owner_protected?(actor, user, channel: Current.channel)
      user.persisted? && user.owner? && !actor_owner?(actor, channel: channel)
    end

    # An owner, or a trusted code path (nil actor on `:setup`/`:console`/
    # `:system`). Never an API token, not even an owner's (final fix wave,
    # Minor 1): a token acts within its group, so an owner's token with
    # `users.manage` can't flip owner flags or edit an owner's account.
    def actor_owner?(actor, channel: Current.channel)
      return AccessControl.trusted?(actor, channel) if actor.nil?

      AccessControl.owner?(actor)
    end

    # Fix round 1 (I1), the same idea one level down: a non-owner may only
    # manage users whose rights are a subset of their own -- every group the
    # target belongs to must be one the actor may manage as it stands
    # (`AccessControl.can_manage_group?`, which a token answers on its
    # effective rights). Otherwise `users.manage` alone would let them reset an
    # Admin member's password or email, sign in as them, and hold every right
    # Admin has. Owners (and trusted code paths) are unaffected; acting on
    # yourself is never "outranked".
    def outranked?(actor, user, channel: Current.channel)
      return false if user.new_record? || actor_owner?(actor, channel: channel) || actor.nil?
      return false if user == (actor.is_a?(ApiToken) ? actor.user : actor)

      AccessControl::Group.includes(:grants).where(id: user.memberships.select(:group_id)).any? do |group|
        !AccessControl.can_manage_group?(actor, group, channel: channel)
      end
    end
  end
end
