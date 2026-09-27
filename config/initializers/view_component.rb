# Component previews (open-types spec §5). `previews.paths` is set
# explicitly rather than relying on the gem's own "if the directory already
# exists at boot" default (`ViewComponent::Config.default_preview_paths`),
# since that check runs before this app's own initializers and would
# otherwise silently do nothing on a fresh checkout before the directory is
# ever created. `previews.controller` points at `ComponentPreviewsController`
# (see its own comment) rather than the gem's default
# `ViewComponentsController`, which has no `public_urls` -- Lookbook reads
# this same setting (it syncs its own `preview_controller` config from
# `ViewComponent::Config.previews.controller`), so this one line covers both
# Lookbook and the preview smoke test.
Rails.application.config.view_component.previews.paths = [ Rails.root.join("test/components/previews").to_s ]
Rails.application.config.view_component.previews.controller = "ComponentPreviewsController"
