class Avo::Resources::Post < Avo::BaseResource
  self.icon = "tabler/outline/ballpen"
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
    field :content_type, as: :select, enum: ::Post.content_types
    field :title, as: :text
    field :slug, as: :text
    field :excerpt, as: :text
    field :published_at, as: :date_time
    field :metadata, as: :code
    field :tags, as: :has_many, through: :post_tags
    field :related_posts, as: :has_many, through: :post_relations
    field :body, as: :trix
  end

  def filters
    filter Avo::Filters::ContentType
  end
end
