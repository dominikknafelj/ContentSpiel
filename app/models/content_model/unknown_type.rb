# Raised by `.fetch` for a name that isn't registered (spec §7). Rendering
# and path-sync boundaries use `.find` and skip with a logged warning
# instead, so a stale record (e.g. a removed plugin's type) never 500s the
# public site -- `fetch` is for call sites that consider an unknown type a
# bug, not a fact of life to route around.
class ContentModel::UnknownType < KeyError; end
