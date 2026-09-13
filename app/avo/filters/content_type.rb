class Avo::Filters::ContentType < Avo::Filters::SelectFilter
  self.name = "Content type"

  def apply(request, query, value)
    return query if value.blank?

    query.where(content_type: value)
  end

  def options
    ::Post.content_types.keys.index_with { |key| key.humanize }.symbolize_keys
  end
end
