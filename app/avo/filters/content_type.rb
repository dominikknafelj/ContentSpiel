class Avo::Filters::ContentType < Avo::Filters::SelectFilter
  self.name = "Content type"

  def apply(request, query, value)
    return query if value.blank?

    query.where(content_type: value)
  end

  # {value => label}, not {label => value}: the base `_select_filter.html.erb`
  # this renders through does `filter.options.invert` before handing the
  # result to `options_for_select` (`{label => value}`, the shape a bare
  # `select_tag`/`options_for_select` Hash always wants -- Avo's own `:select`
  # *field* takes that shape directly, with no invert step, which is the
  # opposite convention and why `Avo::Resources::Post#fields`' own
  # `content_type` field builds its options the other way around). Getting
  # this backwards doesn't fail any request -- `apply` below is handed the
  # submitted value regardless -- it would just show the raw registry name as
  # the visible option text and submit the humanized label as the query value.
  def options
    ::ContentTypes.all.to_h { |definition| [ definition.name, definition.label ] }
  end
end
