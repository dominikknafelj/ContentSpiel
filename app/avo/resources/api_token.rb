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
end
