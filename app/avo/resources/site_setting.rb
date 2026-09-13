class Avo::Resources::SiteSetting < Avo::BaseResource
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
    field :title, as: :text
    field :tagline, as: :text
    field :social_links, as: :code
    field :default_locale, as: :text
    field :logo, as: :file
  end
end
