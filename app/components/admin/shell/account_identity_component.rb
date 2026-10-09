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
    # The block is a LINK to the account screen (the notes handoff's decision
    # 25), where all of this is changed; `url_options` are the address
    # parameters of the page it is drawn on, as for every link of the shell.
    # The name is underlined on hover, as the links under it are.
    #
    # `truncate` plus `title` so a long name or email never widens the column.
    # The email is left out when the name line already is the email (a user
    # without a name falls back to it).
    class AccountIdentityComponent < Admin::AdminComponent
      # How many group names the role line spells out before "+N".
      ROLE_LINE_GROUPS = 2

      erb_template <<~ERB
        <%= link_to helpers.admin_account_password_path(**url_options), id: "account-identity",
              class: "group flex min-w-0 flex-col gap-0.5 rounded-cs no-underline focus-visible:outline-2 focus-visible:outline-accent" do %>
          <span class="truncate text-sm font-medium text-ink underline-offset-2 group-hover:underline" title="<%= user.display_name %>"><%= user.display_name %></span>
          <span class="truncate text-xs text-meta" title="<%= line %>"><%= line %></span>
        <% end %>
      ERB

      def initialize(user:, url_options: {})
        @user = user
        @url_options = url_options
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

      attr_reader :user, :url_options

      def line
        [ (user.email_address if user.display_name != user.email_address), role_line ].compact.join(" · ")
      end
    end
  end
end
