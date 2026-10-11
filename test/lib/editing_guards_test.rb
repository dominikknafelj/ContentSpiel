require "test_helper"

# Two rules of live editing that nothing fails loudly for
# (`docs/reference/live-editing.md`), held by their sources (final review I6).
#
# These are greps, with a grep's limits: each says below what it cannot see.
class EditingGuardsTest < ActiveSupport::TestCase
  MARKUP = Dir[Rails.root.join("app/{components,views,helpers}/**/*.{rb,erb}")].freeze
  SCRIPTS = Dir[Rails.root.join("app/javascript/**/*.js")].freeze

  # `editing_version: <name>` in a data hash, or `data-editing-version="<%= <name> %>"`.
  WRITTEN = /editing_version:\s*(?<value>[^,})\n]+)|data-editing-version="(?<value>[^"]*)"/

  # A catch-up leaves a unit alone when its version equals the answer's, so a
  # version written by hand, or from a stamp of its own, is a unit that stays
  # as it is when it should have been redrawn (or is redrawn on every fetch).
  # Every place that writes the attribute hands it a method of its own
  # component, and that method's body calls `Editing.version`.
  #
  # Not seen: a version built somewhere this does not look (a model, a
  # helper called by another name) and handed in through a variable.
  test "every data-editing-version in the app is written from a method that calls Editing.version" do
    written = MARKUP.flat_map do |path|
      File.read(path).scan(WRITTEN).map { |hash_value, attribute_value| [ path, (hash_value || attribute_value).strip ] }
    end
    assert_operator written.size, :>=, 5, "the pattern no longer finds where the versions are written"

    offences = written.reject do |path, value|
      name = value[/\A(?:<%=\s*)?(\w+)(?:\s*%>)?\z/, 1]
      next false unless name

      component = path.sub(/\.html\.erb\z/, ".rb")
      File.exist?(component) && File.read(component).match?(/def #{name}\b[^\n]*::Editing\.version\(/)
    end
    assert_empty offences.map { |path, value| "#{path.delete_prefix("#{Rails.root}/")}: #{value}" },
      "a unit's version is written from something other than a method that calls Editing.version"

    by_script = SCRIPTS.select { |path| File.read(path).match?(/editingVersion\s*=[^=]|setAttribute\(\s*["']data-editing-version/) }
    assert_empty by_script.map { |path| path.delete_prefix("#{Rails.root}/") }, "a script writes a unit's version (the live script only ever removes one)"
  end

  STATEMENT = /Reservation\.(?:claim|release|request|withdraw|hand_over|pass_over)\b/

  # Who may call a reservation's statements, and whether in a transaction.
  CALLERS = {
    "app/controllers/concerns/admin/editing_claims.rb" => :autocommit, # a save's claim and its give-back, a release: before and after the service, never in its transaction
    "app/controllers/admin/editing_controller.rb" => :autocommit,      # the withdrawal of a request
    "app/services/editing/take_over.rb" => :transaction                # the one transaction: it locks this very row first
  }.freeze

  # A statement locks the one row it touches until the end of the transaction
  # it is in. In autocommit that is the statement itself; inside a service's
  # transaction it would keep the row locked for everyone else's claim until
  # that transaction ends (a held block's strip would hang every colleague's
  # first keystroke).
  #
  # Not seen: a transaction opened further up the call stack than the file
  # the statement is written in. That is why the callers are a closed list:
  # a new one is read by a person before it is added here.
  test "a reservation's statements are called only by the three callers the reference names, in a transaction only in Editing::TakeOver" do
    sources = Dir[Rails.root.join("{app,lib,config}/**/*.rb")].reject { |path| path.end_with?("app/models/editing/reservation.rb") }
    callers = sources.select { |path| strip_comments(File.read(path)).match?(STATEMENT) }.map { |path| path.delete_prefix("#{Rails.root}/") }
    assert_equal CALLERS.keys.sort, callers.sort, "a reservation's statements have a caller this guard does not know (or lost one)"

    CALLERS.each do |path, mode|
      source = strip_comments(Rails.root.join(path).read)
      if mode == :autocommit
        assert_no_match(/\btransaction\b|\bwith_lock\b|\.lock\b|lock!/, source, "#{path} calls a reservation's statements and opens a transaction or takes a lock")
      else
        assert_equal 1, source.scan(/\btransaction\b/).size, "#{path} has one transaction"
        assert_match(/transaction do.*?Reservation\.of\(@subject\)\.lock\.first/m, source, "#{path} locks the reservation's row first in its transaction")
      end
    end
  end

  private

  def strip_comments(source) = source.lines.reject { |line| line.strip.start_with?("#") }.join
end
