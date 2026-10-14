require "test_helper"

# Rules of the theme mechanism that nothing else would notice being broken
# (theming spec §1 and §8).
class ThemeGuardsTest < ActiveSupport::TestCase
  ROOTS = %w[app lib config].freeze

  # The one place outside `Theme` that may set the theme: the last lines of
  # the types' `to_prepare` (the theme is prepared after the types it is
  # checked against, block types spec decision 6), by the exact line it is allowed, so a second assignment in
  # the same file is still found. (`Theme` itself sets `@current`, which is
  # none of the spellings below, so it needs no entry here.)
  ALLOWED = {
    "config/initializers/types.rb" => /\A\s*Theme\.current = Theme\.prepare\(ThemeFolder\.current, reload: ThemeFolder\.booted\? \|\| ThemeFolder\.checking\?, unregistered: unregistered\)\z/
  }.freeze

  # Every way to swap the process's theme: `Theme.with`, an assignment to
  # `Theme.current` (`=`, `||=`, `&&=`), either through `send`, and the
  # variable set from outside. White space, a line break included, may stand
  # around the dot, so a call split over two lines is one call.
  SWAP = /
    \bTheme\s*\.\s*with\b
    | \bTheme\s*\.\s*current\s*(?:\|\||&&)?=(?![=~>])
    | \bTheme\s*\.\s*(?:public_send|send|__send__)\s*\(?\s*[:"'](?:with|current=)
    | \bTheme\s*\.\s*instance_variable_set\b
  /x

  # Code without its comments: an ERB comment, and a Ruby line that is one
  # (blanked, not removed, so line numbers stay).
  def code_of(text) = text.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, " ") }.gsub(/^\s*#.*$/, "")

  # `sources` is { relative path => text }; the answer names each match of
  # `pattern` by file, line and the line's text.
  def found_in(sources, pattern, allowed: {})
    sources.flat_map do |file, text|
      code = code_of(text)
      lines = code.lines
      code.enum_for(:scan, pattern).filter_map do
        number = code[0, Regexp.last_match.begin(0)].count("\n") + 1
        line = lines[number - 1].to_s.chomp
        next if allowed[file]&.match?(line)

        "#{file}:#{number}: #{line.strip}"
      end
    end
  end

  def swaps_in(sources) = found_in(sources, SWAP, allowed: ALLOWED)

  # A Theme built without the check. Outside `Theme` itself, which is where
  # `load` and `prepare` build theirs.
  def unchecked_in(sources) = found_in(sources.except("app/values/theme.rb"), /\bTheme\s*\.\s*new\b/)

  def application_sources
    ROOTS.flat_map { |root| Dir.glob(Rails.root.join(root, "**/*.{rb,erb,rake,ru}").to_s) }.to_h do |file|
      [ Pathname(file).relative_path_from(Rails.root).to_s, File.read(file) ]
    end
  end

  # `Theme.current` is one variable of the process, not of a request or a
  # thread: swapped while a request is being answered, every other request
  # of the process is drawn by the other theme, and its ETag names it.
  test "nothing in the application swaps the theme: Theme.with and Theme.current= are the tests' and the initializer's" do
    sources = application_sources

    assert_operator sources.size, :>, 500
    assert_empty swaps_in(sources), "Theme.with and Theme.current= are process-wide, for tests and the boot only. " \
                                    "Application code asks Theme.current and never sets it"
  end

  test "every entry of the allow-list still allows a line that is there" do
    sources = application_sources

    ALLOWED.each do |file, line|
      assert_equal 1, found_in(sources.slice(file), SWAP).count { |found| line.match?(found.split(": ", 2).last) },
        "#{file} no longer holds the one swap the allow-list is for: correct the entry or delete it"
    end
  end

  test "the guard can fail: a swap in a controller, a view, a job or a second one in the initializer is named with its line" do
    found = swaps_in(
      "app/controllers/pages_controller.rb" => "class X\n  # Theme.with(other) in a comment\n  def show = Theme.with(other) { render }\nend\n",
      "app/views/pages/show.html.erb" => "<%# Theme.current = x %>\n<% Theme.current = Theme.new %>\n",
      "app/jobs/x_job.rb" => "Theme.send(:with, theme) { }\nTheme.current == theme\nTheme.current ||= theme\nTheme\n  .with(theme) { }\n",
      "app/models/x.rb" => "Theme.instance_variable_set(:@current, theme)\nTheme.current =\n  theme\nx = { Theme.current => 1 }\n",
      "config/initializers/types.rb" => "  Theme.current = Theme.prepare(ThemeFolder.current, reload: ThemeFolder.booted? || ThemeFolder.checking?, unregistered: unregistered)\nTheme.current = Theme.new\n",
      "app/values/theme.rb" => "    def with(theme)\n      @current = theme\n"
    )

    assert_equal [
      "app/controllers/pages_controller.rb:3: def show = Theme.with(other) { render }",
      "app/views/pages/show.html.erb:2: <% Theme.current = Theme.new %>",
      "app/jobs/x_job.rb:1: Theme.send(:with, theme) { }",
      "app/jobs/x_job.rb:3: Theme.current ||= theme",
      "app/jobs/x_job.rb:4: Theme",
      "app/models/x.rb:1: Theme.instance_variable_set(:@current, theme)",
      "app/models/x.rb:2: Theme.current =",
      "config/initializers/types.rb:2: Theme.current = Theme.new"
    ], found
  end

  # `Theme.load` (and `Theme.prepare`, which is `load` with a reload's
  # answer) is the one door a folder becomes the application's theme
  # through, and the check is in it (`test/values/theme/check_test.rb`:
  # "load refuses a folder with a problem"). `Theme.new(path:)` checks
  # nothing, which is what a test of the rendering itself wants and what the
  # application must never do.
  test "the application makes a theme of a folder through Theme.load only, so no folder goes unchecked" do
    assert_empty unchecked_in(application_sources), "Theme.new outside Theme itself: a folder handed to it is not checked against the contract"
  end

  test "that guard can fail too: Theme.new in a controller or an initializer is named, and Theme's own and a comment are not" do
    found = unchecked_in(
      "app/controllers/pages_controller.rb" => "# Theme.new(path: x) in a comment\ntheme = Theme.new(path: params[:theme])\n",
      "config/initializers/types.rb" => "Theme.current = Theme\n  .new(path: ENV[\"THEME_PATH\"])\n",
      "app/values/theme.rb" => "Theme.new\n",
      "app/models/x.rb" => "ThemeFolder.new(x)\nOtherTheme.new\n"
    )

    assert_equal [
      "app/controllers/pages_controller.rb:2: theme = Theme.new(path: params[:theme])",
      "config/initializers/types.rb:1: Theme.current = Theme"
    ], found
  end
end
