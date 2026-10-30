module Admin
  module GroupsScreen
    # The group editor's Members field (round 3 Task 11, handoff §4.7 and decision
    # D16): a chip multi-select -- `Admin::Ui::ChipInputComponent` over
    # `GET /<admin>/users/suggest` -- instead of a checkbox per user, so a site with
    # many users doesn't render all of them.
    #
    # The form's source of truth is the chips' hidden inputs
    # (`group[member_ids][]`), plus the component's blank sentinel ahead of them so
    # an emptied list still submits as empty (`Admin::GroupsController#group_attributes`
    # reads absent as "not given"). They are TRACKED (`track: true`), so the footer
    # counts adding or removing a member and nothing else: typing in the search box
    # is swallowed by the chip input and has no name.
    #
    # OWNERS. The suggestions never offer one ("Owners aren't listed: they already
    # have every permission"), but an owner who is ALREADY a member is drawn as a
    # chip like anyone else and stays until someone removes it, so an untouched save
    # keeps them (`Groups::Save` replaces the list wholesale; leaving a stored member
    # out would silently remove them). Whether the viewer may add or remove a given
    # member is `Groups::Save`'s call -- a refusal is the 403 page -- and is not
    # second-guessed here.
    #
    # INVITED people (mail spec "Invites") are members like anyone else, since
    # an invite may put someone into groups; their chip says "Invited", as an
    # owner's says "Owner", because they cannot sign in until they accept.
    #
    # `users`: the members to show as chips, in the order given.
    class MembersComponent < AdminComponent
      HELP = "Owners aren't listed: they already have every permission.".freeze

      def initialize(users:, search_url:, errors: [])
        @users = users
        @search_url = search_url
        @errors = errors
      end

      private

      attr_reader :users, :search_url, :errors

      # The name, with the email as the muted hint after it; a user with no name
      # is already shown by their email, so nothing is repeated. An owner says so.
      def chips
        users.map do |user|
          hint = [ ("Owner" if user.owner?), ("Invited" if user.invited?), (user.email_address if user.name.present?) ].compact.join(" · ").presence
          { value: user.id.to_s, label: user.display_name, hint: hint }
        end
      end
    end
  end
end
