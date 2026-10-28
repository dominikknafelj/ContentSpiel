# Counts the HTML sanitizer's parses (`Loofah.html5_fragment`, the first
# step of `Rails::HTML5::SafeListSanitizer#sanitize` and of
# `RichText::HtmlRenderer#render_fragments`) while a block runs, and nothing
# outside one: the suite has no mocking library, and a parse is what a
# sanitizer pass costs. `SanitizerParses.during { ... }` answers the block's
# value and the number of parses.
module SanitizerParses
  def self.during
    Thread.current[:sanitizer_parses] = 0
    [ yield, Thread.current[:sanitizer_parses] ]
  ensure
    Thread.current[:sanitizer_parses] = nil
  end

  def html5_fragment(...)
    Thread.current[:sanitizer_parses] += 1 if Thread.current[:sanitizer_parses]
    super
  end
end

Loofah.singleton_class.prepend(SanitizerParses)
