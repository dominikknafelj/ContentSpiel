require "test_helper"

# Where a screen's parts live (docs/superpowers/specs/2026-10-10-source-layout-cleanup-design.md).
# A Stimulus identifier follows its controller's path, and a name left behind
# by a move does not raise: the control is just dead. So every identifier the
# app writes must have a controller file.
class SourceLayoutTest < ActiveSupport::TestCase
  ROOT = Rails.root
  CONTROLLERS = ROOT.join("app/javascript/controllers")
  SOURCES = %w[app/components app/views app/helpers app/javascript app/assets/tailwind].freeze
  TOKEN = /(?<![a-z0-9-])admin--[a-z0-9]+(?:-{1,2}[a-z0-9]+)*/

  # Prose in a comment may wrap an identifier across lines; only code is scanned.
  COMMENT_LINE = %r{^\s*(?:#|//).*$}

  def self.identifiers
    Dir[CONTROLLERS.join("**/*_controller.js")].map do |path|
      Pathname(path).relative_path_from(CONTROLLERS).to_s.delete_suffix("_controller.js").gsub("/", "--").tr("_", "-")
    end
  end

  # The identifier a token belongs to: the longest one it equals or extends with "-".
  def self.owner(token, identifiers)
    identifiers.select { |id| token == id || token.start_with?("#{id}-") }.max_by(&:length)
  end

  test "every admin identifier written in the app has a controller file" do
    identifiers = self.class.identifiers
    orphans = SOURCES.flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb,js,css}")] }.flat_map do |path|
      File.read(path).gsub(COMMENT_LINE, "").scan(TOKEN).uniq.reject { |token| self.class.owner(token, identifiers) }.map { |token| "#{Pathname(path).relative_path_from(ROOT)}: #{token}" }
    end
    assert_empty orphans, "identifiers with no controller file:\n#{orphans.join("\n")}"
  end

  test "the guard's own matching: an identifier, its targets and values, and a stranger" do
    ids = %w[admin--notes admin--notes-live]
    assert_equal "admin--notes-live", self.class.owner("admin--notes-live-unread-url-value", ids)
    assert_equal "admin--notes", self.class.owner("admin--notes-target", ids)
    assert_nil self.class.owner("admin--nothing", ids)
  end
end
