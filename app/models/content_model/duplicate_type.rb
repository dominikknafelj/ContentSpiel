# Raised by `.register` for a name that's already registered (spec §3.2a) --
# a developer error caught at boot, distinct from `UnknownType`. The one
# legitimate re-registration, a `to_prepare` reload, always calls `reset!`
# first (config/initializers/types.rb, Task 2), so this only fires for an
# actual duplicate, e.g. two plugins claiming the same name.
class ContentModel::DuplicateType < StandardError; end
