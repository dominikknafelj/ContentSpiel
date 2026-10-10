require "test_helper"

# Every script that writes class names is one the Tailwind build reads.
# `app/assets/tailwind/application.css` is `source(none)` plus explicit
# `@source` lines, so a directory of scripts that is not named there is not
# scanned: a utility used only in it is simply not in the built stylesheet,
# and nothing fails. That shipped once: `w-fit` was used only in
# `mind_graph/card.js` and `app.js`, so each notice line over the graph was a
# bar as wide as its container and each link of the card stretched across it,
# and a click beside the text navigated.
#
# So: every file under `app/javascript` that sets an element's classes
# (`className =`, `classList`, `setAttribute("class", …)`, a `class:` key) is
# under a path an `@source` line names. What this can't see is a file that
# only hands class strings to another module's helper; today each such string
# sits in a file that also sets `className` itself.
class TailwindSourcesTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/application.css")
  WRITES_CLASSES = /className\s*\+?=|\bclassList\b|setAttribute\(\s*["']class["']|\bclass:\s*["'`]/

  # A script that names only classes written by hand in the stylesheets, so
  # there is nothing in it for the build to find. Each entry says which.
  HAND_WRITTEN_ONLY = {
    "app/javascript/saving/promotion_hold.js" => "`admin-spinner`, defined in content-spiel.tailwind.css"
  }.freeze

  def sources
    File.read(STYLESHEET).scan(/^@source\s+"([^"]+)";/).flatten.map { |path| STYLESHEET.dirname.join(path).cleanpath.to_s }
  end

  def scripts_writing_classes
    Dir[Rails.root.join("app/javascript/**/*.js")].select { |path| File.read(path).match?(WRITES_CLASSES) }
  end

  def covered?(path, by) = by.any? { |source| path == source || path.start_with?("#{source}/") }

  test "every script that writes class names is under an @source path" do
    scripts = scripts_writing_classes
    assert_operator scripts.size, :>, 15, "the sources moved: this guard is looking at too little"

    by = sources
    unread = scripts.reject { |path| covered?(path, by) }.map { |path| Pathname(path).relative_path_from(Rails.root).to_s } - HAND_WRITTEN_ONLY.keys

    assert_empty unread, "The Tailwind build does not read these scripts, so a utility class used only there is not built " \
                         "(add an @source line to #{STYLESHEET.relative_path_from(Rails.root)}):\n#{unread.join("\n")}"
  end

  test "every @source path exists" do
    missing = sources.reject { |path| File.exist?(path) }

    assert_empty missing, "An @source line names nothing: #{missing.join(", ")}"
  end

  test "the allow-list holds only scripts that are still outside the sources and still write classes" do
    by = sources
    stale = HAND_WRITTEN_ONLY.keys.reject do |relative|
      path = Rails.root.join(relative).to_s
      File.exist?(path) && File.read(path).match?(WRITES_CLASSES) && !covered?(path, by)
    end

    assert_empty stale, "Remove from HAND_WRITTEN_ONLY: #{stale.join(", ")}"
  end
end
