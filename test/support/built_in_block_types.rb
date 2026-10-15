# The built-in block types as config/initializers/types.rb calls them, in the
# order of its lines: `BlockTypes::RichText.register` is `rich_text`. Read
# from the initializer's source, not from the registry, so a test that asks
# whether the built-ins are registered, and in which order, compares the
# registry with something the registry cannot change: a reload that stopped
# half way, or a type registered in another place, fails it. A new built-in
# (the generator's line) is in it the day its line is written.
module BuiltInBlockTypes
  INITIALIZER = Rails.root.join("config/initializers/types.rb")

  def self.names
    INITIALIZER.read.scan(/^\s*BlockTypes::(\w+)\.register\s*$/).flatten.map(&:underscore)
  end
end
