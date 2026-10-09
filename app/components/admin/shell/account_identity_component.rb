module Admin
  module Shell
    # Who is signed in, as the sidebar's account block says it: the display
    # name, then "email · role" on one line (handoff: "name, email and role").
    # Its own component, with an id, because it is the one part of the shell a
    # save on the account screen changes: its "Save" answers with a Turbo
    # Stream that replaces just this (`Admin::AccountsController
    # #update_profile`), so the screen -- and whatever the password form
    # beside the name holds -- stays as it is.
    #
    # `truncate` plus `title` so a long name or email never widens the column.
    # The email is left out when the name line already is the email (a user
    # without a name falls back to it).
    class AccountIdentityComponent < Admin::AdminComponent
      # How many group names the role line spells out before "+N".
      ROLE_LINE_GROUPS = 2

      erb_template <<~ERB
        <div id="account-identity" class="flex min-w-0 flex-col gap-0.5">
          <span class="truncate text-sm font-medium text-ink" title="<%= user.display_name %>"><%= user.display_name %></span>
          <span class="truncate text-xs text-meta" title="<%= line %>"><%= line %></span>
        </div>
      ERB

      def initialize(user:)
        @user = user
      end

      # "Owner", or up to two group names then "+N", or "No groups" -- what
      # the account block says this user is, in one short mono line.
      def role_line
        return "Owner" if user.owner?

        names = user.groups.map(&:name)
        return "No groups" if names.empty?

        line = names.first(ROLE_LINE_GROUPS).join(", ")
        names.size > ROLE_LINE_GROUPS ? "#{line} +#{names.size - ROLE_LINE_GROUPS}" : line
      end

      private

      attr_reader :user

      def line
        [ (user.email_address if user.display_name != user.email_address), role_line ].compact.join(" · ")
      end
    end
  end
end
