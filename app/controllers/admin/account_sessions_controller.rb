module Admin
  # The Sessions card's two endings on Your account
  # (`Admin::AccountScreen::SessionsCardComponent`): a row's End, and "Sign
  # out everywhere else". Open to every signed-in user, for their own
  # sessions only: the request names a session, never a user, and
  # `Sessions::EndOthers` looks the id up among `Current.user`'s.
  #
  # The session the request is made in is always the one kept
  # (`keep: Current.session`), so neither ending signs the person out here:
  # a crafted End of the current session's id ends nothing.
  class AccountSessionsController < BaseController
    # A row's End. An id that ended nothing (another user's, one already
    # gone, this session's own) is answered exactly as one of the person's
    # that had already ended -- the same stream, the same words -- so the
    # answer says nothing about whose the id was. The row is taken away
    # either way: whatever it named is not a session of theirs to end.
    def destroy
      ended = end_sessions(only: params[:id])
      message = ended.positive? ? t("admin.accounts.sessions.ended") : t("admin.accounts.sessions.already_ended")

      if request.accepts.any? { |type| type.symbol == :turbo_stream }
        # The foot first, then the row: `admin--account--sessions` hands
        # the focus on when the row goes, and may hand it to the foot's
        # button, which must be the new foot's by then.
        render turbo_stream: [
          turbo_stream.replace(AccountScreen::SessionsFootComponent::ID,
            AccountScreen::SessionsFootComponent.new(others: other_sessions_count, url_options: admin_url_options)),
          turbo_stream.remove("session-#{params[:id].to_i}"),
          Admin::ToastStream.for(turbo_stream, message)
        ]
      else
        redirect_to admin_account_path(**admin_url_options, anchor: AccountScreen::SessionsCardComponent::HEADING_ID), status: :see_other, notice: message
      end
    end

    # "Sign out everywhere else": every session of the person's but this one.
    # Back to the card with the count, as a redirect, since the whole card
    # changes.
    def destroy_others
      ended = end_sessions
      redirect_to admin_account_path(**admin_url_options, anchor: AccountScreen::SessionsCardComponent::HEADING_ID), status: :see_other,
        notice: t("admin.accounts.sessions.ended_others", count: ended)
    end

    private

    # How many sessions ended. `Sessions::EndOthers` refuses only an actor
    # that is not the user, which a signed-in person's own request never is;
    # a refusal would have ended nothing, and is counted as that.
    def end_sessions(only: nil)
      result = Sessions::EndOthers.call(user: Current.user, keep: Current.session, only: only)
      result.ok? ? result.record : 0
    end

    def other_sessions_count = Current.user.sessions.live(Time.current).where.not(id: Current.session.id).count
  end
end
