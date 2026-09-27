# Built-in block types, content types and field groups (open-types spec §3.1),
# registered through the same calls plugins will use. Inside `to_prepare` so
# a code reload in development re-registers against the freshly loaded
# classes; the registries are reset first, so nothing is registered twice
# (`register` itself raises `ContentModel::DuplicateType` on a name that's
# already taken -- see `ContentModel::Registry#register`).
Rails.application.config.to_prepare do
  [ BlockTypes, ContentTypes, FieldGroups ].each(&:reset!)

  BlockTypes::RichText.register
  BlockTypes::Image.register
  BlockTypes::PostList.register

  # Registration order matters: it defines `names` order and
  # `ContentTypes.default` (the first one registered -- `blog`).
  ContentTypes::Blog.register
  ContentTypes::ResumeEntry.register
  ContentTypes::NowUpdate.register
end
