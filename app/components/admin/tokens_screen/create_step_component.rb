module Admin
  module TokensScreen
    # Step 1 of the AI assistant page, "Create a token": a Name (required,
    # 1-60 characters, round 3 decision D2), a Group select with the selected
    # group's description on one line beneath (every option carries it in
    # `data-description`, `admin--tokens--group-hint` swaps the text, so no request),
    # and Create token.
    #
    # The form is a plain, non-Turbo POST (`data-turbo="false"`): the answer to
    # a successful create is a rendered document holding the raw token, which
    # a Turbo form submission would refuse (it demands a redirect) and a
    # redirect must never carry. With `raw_token:` -- only ever the
    # create response -- this step also shows the warn box, the token itself
    # (`#api-token-value`, blanked on `pagehide` by `admin--tokens--reveal`) and
    # Copy token; the form stays below it so another can be made.
    #
    # `name_errors:` / `group_errors:` print under their own field (a failed
    # create re-renders at 422 with the typed `name:` kept); `selected_id:`
    # keeps the chosen group across that re-render.
    class CreateStepComponent < Admin::AdminComponent
      NAME_ERROR_ID = "token-name-error".freeze
      GROUP_ERROR_ID = "token-group-error".freeze

      def initialize(groups:, form_url:, selected_id: nil, name: "", name_errors: [], group_errors: [], raw_token: nil)
        @groups = groups
        @form_url = form_url
        @selected_id = selected_id
        @name = name
        @name_errors = Array(name_errors)
        @group_errors = Array(group_errors)
        @raw_token = raw_token
      end

      private

      attr_reader :groups, :form_url, :name, :name_errors, :group_errors, :raw_token

      def selected_group = groups.find { |group| group.id == @selected_id } || groups.first

      def selected_description = selected_group&.description.to_s

      def name_described_by = name_errors.any? ? NAME_ERROR_ID : nil
    end
  end
end
