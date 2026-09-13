class Avo::Resources::ApiToken < Avo::BaseResource
  # self.icon = "tabler/outline/users"
  # self.avatar = {
  #   source: :avatar
  # }
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    # field :avatar, as: :avatar
    # `disabled:` (not `readonly:`) so the bcrypt digest is ignored on save --
    # editing it by hand would silently invalidate the token.
    field :token_digest, as: :text, disabled: true
    field :revoked_at, as: :date_time
  end

  # Tokens are minted by ApiToken.generate!, which is what hashes the raw token
  # into the NOT NULL `token_digest` column -- a hand-filled New form could only
  # ever raise NotNullViolation. Avo 4.2.3 Community has no `new_enabled` flag
  # (per-action gating lives in the avo-authorization plugin, which isn't
  # installed and stubs out to "always allowed"), so the Create button is
  # dropped from the index controls here and Avo::ApiTokensController turns the
  # new/create routes away. Both halves are needed: hiding the button alone
  # leaves the route reachable.
  def render_index_controls(item:)
    super.reject { |control| control.is_a?(Avo::Resources::Controls::CreateButton) }
  end
end
