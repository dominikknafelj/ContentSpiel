module Admin
  module GroupsScreen
    # The Groups list: one card holding a table of every group, with its
    # members and its tokens. A group's row is pressed anywhere: the name is
    # the row's one link (`.admin-row-link`, whose cover reaches the whole
    # row), with the Built-in badge beside it and the description beneath,
    # and the row ends in the verb "Edit", words describing that link. There
    # is no Delete: it lives in the editor's own zone.
    #
    # A count reads as a number, in meta at zero, with its noun for a screen
    # reader alone ("3 members").
    #
    # `member_counts` and `token_counts` are `{ group_id => n }` from ONE grouped
    # query each (`Admin::GroupsController#index`): no per-row count. Tokens
    # counts the ACTIVE tokens bound to the group (a revoked one is not a thing
    # the group's delete still has to revoke).
    class ListComponent < AdminComponent
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
