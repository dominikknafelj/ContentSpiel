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

  # The Tiptap node/mark schema (design spec §3.2) -- a separate registry
  # from the three above (`RichText::Schema`, not `ContentModel::Registry`),
  # but reset-then-register for the exact same reason: a code reload in
  # development must re-register the built-ins cleanly instead of raising
  # `RichText::DuplicateType` against whatever's still sitting in the
  # registry from before the reload.
  RichText::Schema.reset!
  RichText::BuiltIns.register

  # The permission registry (access-control design spec §3.1) -- a third,
  # independent registry, reset-then-register for the exact same reason as
  # the two above: a code reload in development must re-register the
  # built-in permissions cleanly instead of raising
  # `AccessControl::DuplicatePermission` against whatever's still sitting
  # in the registry from before the reload.
  AccessControl::Permissions.reset!
  AccessControl::BuiltIns.register

  # The AI provider registry (translation helpers spec §6.1) -- reset then
  # register, for the same reason as every registry above
  # (`AI::DuplicateProvider` otherwise, after a development reload).
  AI::Providers.reset!
  AI::Providers.register("anthropic", AI::Providers::Anthropic)
end
