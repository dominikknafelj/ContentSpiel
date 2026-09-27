class Avo::Filters::ContentType < Avo::Filters::SelectFilter
  self.name = "Content type"

  def apply(request, query, value)
    return query if value.blank?

    query.where(content_type: value)
  end

  def options
    ::ContentTypes.names.index_with { |name| name.humanize }.symbolize_keys
  end
end
