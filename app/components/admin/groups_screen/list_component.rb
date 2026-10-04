module Admin
  module GroupsScreen
    # The Groups list (round 3 Task 10, handoff §4.7 / `Studio Groups.dc.html`):
    # a card of rows -- name (with its "Built-in" tag and description), members,
    # tokens -- where the WHOLE row is the link to the group's editor. The name
    # is the one anchor, stretched over the row by a pseudo-element
    # (`after:absolute after:inset-0` on a `relative` row), so there is no Edit
    # button and nothing interactive nested inside another.
    #
    # `member_counts` and `token_counts` are `{ group_id => n }` from ONE grouped
    # query each (`Admin::GroupsController#index`): no per-row count. Tokens
    # counts the ACTIVE tokens bound to the group (a revoked one is not a thing
    # the group's delete still has to revoke).
    class ListComponent < AdminComponent
      COLUMNS = "grid grid-cols-[minmax(0,1fr)_5rem_5rem_1rem] items-center gap-3 px-4".freeze

      def initialize(groups:, member_counts:, token_counts:)
        @groups = groups
        @member_counts = member_counts
        @token_counts = token_counts
      end

      private

      attr_reader :groups, :member_counts, :token_counts

      # The editing language rides along when the layout has one (`admin_url_options`); a preview has no controller.
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
      def members(group) = member_counts.fetch(group.id, 0)
      def tokens(group) = token_counts.fetch(group.id, 0)
      def count_class(count) = count.zero? ? "text-meta" : "text-ink"
    end
  end
end
