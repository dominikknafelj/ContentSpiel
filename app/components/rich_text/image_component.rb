module RichText
  # `<figure><img><figcaption>` for an `image{asset_id, alt, caption}` node
  # (design spec §3.3), rendered through `Media::PictureComponent` (media
  # library Task 5) for a real `srcset`/`sizes` rather than a single
  # original-sized `<img>`.
  #
  # `alt_override`/`caption_override` are the node's own `alt`/`caption`
  # attrs, resolved against `asset`'s own defaults through `Media::Asset
  # #alt_text`/`#caption_text` -- exactly the "override, then the asset's
  # default" chain `Blocks::ImageComponent` already applies for a block's
  # image, now shared by both since a rich-text embed and a block are the
  # same kind of placement over the same library (media library design spec
  # §3.1). Deliberately still not shaped like `Blocks::ImageComponent`
  # itself (which reads `translated(block, :alt)` through Mobility): a
  # rich-text `image` node's overrides are plain attrs already resolved off
  # the node by the time `RichText::HtmlRenderer` gets here, not per-locale
  # translated columns on an ActiveRecord model -- so this component
  # resolves them directly rather than taking a `block:`/`page:` pair it
  # has no use for.
  class ImageComponent < ApplicationComponent
    # `sizes` mirrors `Blocks::ImageComponent`'s own choice, not
    # independently picked: a rich-text image and a block image both render
    # at the same content width, inside the same `max-w-3xl` (768px) column
    # (`app/views/layouts/application.html.erb`) -- see that component's own
    # comment for the full reasoning.
    SIZES = Blocks::ImageComponent::SIZES

    # `locale:` defaults to the ambient `I18n.locale` -- true for every
    # production render (`PublicPageRendering#render_in_requested_locale`
    # sets it for the whole request) -- but `RichText::HtmlRenderer` walks a
    # document under whatever locale its `RenderContext` was built with
    # (`RichText::Document#to_html(locale:, ...)`), which isn't always the
    # ambient one: `Admin::Columns::RichTextColumnComponent#original_html`
    # explicitly renders the *default*-locale document as a read-only
    # comparison while an editor translates some other locale. `RichText
    # ::BuiltIns.render_image` passes `ctx.locale` through explicitly for
    # exactly that reason, rather than leaving this to read `I18n.locale` on
    # its own.
    def initialize(asset:, alt_override: nil, caption_override: nil, locale: I18n.locale)
      @asset = asset
      @alt_override = alt_override
      @caption_override = caption_override
      @locale = locale
    end

    private

    attr_reader :asset

    def alt = asset.alt_text(override: @alt_override, locale: @locale)

    def caption = asset.caption_text(override: @caption_override, locale: @locale)
  end
end
