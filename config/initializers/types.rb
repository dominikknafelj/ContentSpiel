# Built-in block types, content types and field groups (open-types spec §3.1),
# registered through the same calls plugins will use. Inside `to_prepare` so
# a code reload in development re-registers against the freshly loaded
# classes; the registries are reset first, so nothing is registered twice
# (`register` itself raises `ContentModel::DuplicateType` on a name that's
# already taken -- see `ContentModel::Registry#register`). The block types
# from outside the CMS, which a gem hands to `ContentSpiel::Plugins.block_types`
# once, are replayed here after the built-ins on every run, and the theme is
# prepared last, because its check reads the types registered above it.
Rails.application.config.to_prepare do
  # On a development reload (`ThemeFolder.booted?`), a registration that
  # raises (a definition being edited) is kept for the theme below, which
  # says it on every public page, as it says a refused folder: raised here
  # it would end this block before the theme is prepared, and
  # `Theme.current` would stay the last reload's, over classes this reload
  # threw away. The registries after the one that raised stay empty until
  # the next reload. At boot it is raised, and the application does not
  # start.
  unregistered = nil
  begin
    [ BlockTypes, ContentTypes, FieldGroups ].each(&:reset!)

    BlockTypes::RichText.register
    BlockTypes::Image.register
    BlockTypes::Code.register
    BlockTypes::PostList.register
    BlockTypes::Section.register
    # bin/rails generate block_type adds a built-in's line above this one.

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

    # Block types from outside the CMS, after every built-in, in the order
    # their hooks were called (lib/content_spiel/plugins.rb). That is the
    # picker's order too. LAST of the block: a gem whose hook raises on a
    # development reload then leaves every registry of the CMS filled, and
    # only its own block types (and those of the hooks after it) missing.
    ContentSpiel::Plugins.register_block_types(BlockTypes)
  rescue StandardError => error
    raise unless ThemeFolder.booted?

    unregistered = error
  end

  # The site's theme, LAST (block types spec, decision 6): its check reads
  # `Theme::Contract`, whose block lines are the types registered above. The
  # first run raises and every later one does not (`Theme.prepare`);
  # `bin/rails theme:check` is the one boot that does not raise either
  # (`ThemeFolder.checking`).
  Theme.current = Theme.prepare(ThemeFolder.current, reload: ThemeFolder.booted? || ThemeFolder.checking?, unregistered: unregistered)
  # Not under `theme:check`, which says the list itself, once and whole.
  Rails.logger.error("[ContentSpiel] #{Theme.current.refusal.message}") if Theme.current.refusal && !ThemeFolder.checking?
end
