# Namespace for the rich-text subsystem (design spec §3): a schema registry
# that built-ins and, later, plugins register node/mark types against
# (`RichText::Schema`), a value object around a Tiptap/ProseMirror JSON
# document (`RichText::Document`), and -- from Task 2 onward -- the
# renderers and Markdown converters that walk a document through that
# schema. Nothing here talks to ActiveRecord directly; `posts.body` and
# `content_blocks.body` (the only two rich-text columns, spec §3.1) wrap
# their raw jsonb in a `RichText::Document` at the model boundary.
#
# `YOUTUBE_ID_PATTERN` lives on the namespace module, not on `BuiltIns` or
# `NodeType`, because more than the `youtube` node's own `id` attribute
# needs it: its `html` renderer re-checks every id against it, and the
# ActionText importer (`RichText::HtmlImport`) only emits a node whose id
# passes it -- the rule the retired `YoutubeEmbed` model used to own
# (design spec §5). One shared constant is what keeps "a valid stored id"
# and "an id the embed will render" from drifting apart. An 11-character id
# built from letters, digits, `-` and `_` is YouTube's actual video-id
# shape.
module RichText
  YOUTUBE_ID_PATTERN = /\A[\w-]{11}\z/

  # Raised by `Schema.register_node`/`.register_mark` for a name that's
  # already taken (design spec §3.2) -- a developer error caught at boot,
  # mirroring `ContentModel::DuplicateType` for the content-model registries.
  # The one legitimate re-registration, a `to_prepare` reload, always calls
  # `Schema.reset!` first (config/initializers/types.rb), so this only fires
  # for an actual duplicate, e.g. two plugins claiming the same node name.
  #
  # Kept here on the namespace module rather than in its own file: unlike
  # `ContentModel::DuplicateType`, which is the *only* thing its registry
  # needs beyond the shared `ContentModel::Registry` mixin, `RichText::Schema`
  # has enough registry-shaped code of its own (two registries, a different
  # name format, node vs. mark types) that it doesn't reuse that mixin --
  # there's no single natural "the registry file" for this error to live
  # next to instead.
  class DuplicateType < StandardError; end
end
