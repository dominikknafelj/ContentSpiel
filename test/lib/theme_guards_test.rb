require "test_helper"

# Rules of the theme mechanism that nothing else would notice being broken
# (theming spec §1 and §8).
class ThemeGuardsTest < ActiveSupport::TestCase
  ROOTS = %w[app lib config].freeze

  # The two places that may: `Theme` defines both, and the initializer's
  # `to_prepare` assigns the application's theme. Each with the one pattern
  # it is allowed, so a second use in the same file is still found.
  ALLOWED = {
    "app/values/theme.rb" => /\A\s*def with\(theme\)\z|\A\s*@current = (theme|before)\z/,
    "config/initializers/theme.rb" => /\A\s*Theme\.current = Theme\.load\(ThemeFolder\.current\)\z/
  }.freeze

  SWAP = /\bTheme\s*\.\s*with\b|\bTheme\s*\.\s*current\s*=(?!=)|\bTheme\s*\.\s*(?:public_)?send\s*\(\s*:(?:with|current=)/

  # `sources` is { relative path => text }. Comments are not code: a Ruby
  # line that is one, and an ERB comment.
  def swaps_in(sources)
    sources.flat_map do |file, text|
      text.gsub(/<%#.*?%>/m, "").each_line.with_index(1).filter_map do |line, number|
        code = line.chomp
        next if code.match?(/\A\s*#/) || !code.match?(SWAP)
        next if ALLOWED[file]&.match?(code)

        "#{file}:#{number}: #{code.strip}"
      end
    end
  end

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
    assert_match(/Theme\.current = Theme\.load/, sources.fetch("config/initializers/theme.rb"), "the allowed assignment is still there")
  end

  test "the guard can fail: a swap in a controller, a view, a job or a second one in the initializer is named with its line" do
    found = swaps_in(
      "app/controllers/pages_controller.rb" => "class X\n  # Theme.with(other) in a comment\n  def show = Theme.with(other) { render }\nend\n",
      "app/views/pages/show.html.erb" => "<%# Theme.current = x %>\n<% Theme.current = Theme.new %>\n",
      "app/jobs/x_job.rb" => "Theme.send(:with, theme) { }\nTheme.current == theme\n",
      "config/initializers/theme.rb" => "  Theme.current = Theme.load(ThemeFolder.current)\nTheme.current = Theme.new\n",
      "app/values/theme.rb" => "    def with(theme)\n      @current = theme\n"
    )

    assert_equal [
      "app/controllers/pages_controller.rb:3: def show = Theme.with(other) { render }",
      "app/views/pages/show.html.erb:2: <% Theme.current = Theme.new %>",
      "app/jobs/x_job.rb:1: Theme.send(:with, theme) { }",
      "config/initializers/theme.rb:2: Theme.current = Theme.new"
    ], found
  end

  # `Theme.load` is the one door a folder becomes the application's theme
  # through, and the check is in it (`test/values/theme/check_test.rb`:
  # "load refuses a folder with a problem"). `Theme.new(path:)` checks
  # nothing, which is what a test of the rendering itself wants and what the
  # application must never do.
  test "the application makes a theme of a folder through Theme.load only, so no folder goes unchecked" do
    built = application_sources.reject { |file, _| file == "app/values/theme.rb" }.flat_map do |file, text|
      text.each_line.with_index(1).filter_map do |line, number|
        "#{file}:#{number}" if !line.match?(/\A\s*#/) && line.match?(/\bTheme\.new\b/)
      end
    end

    assert_empty built, "Theme.new outside Theme itself: a folder handed to it is not checked against the contract"
  end
end
