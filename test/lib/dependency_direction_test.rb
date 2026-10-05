require "test_helper"
require "ripper"

# The direction of dependency (CLAUDE.md, "Dependency order"): models, queries
# and services know nothing of components, controllers or the application's
# routes. A screen is rebuilt far more often than a rule, and a model that
# renders, or a query that builds a URL, has to be rewritten with every screen
# that shows it -- and can't be used from MCP, a job or the console, where
# there is no view.
#
# What this fails on, under `app/models`, `app/queries` and `app/services`
# (comments stripped, so prose may mention any of these):
#
#   - a `...Component` constant
#   - `ApplicationController` and `ActionController`
#   - `url_helpers` and `Rails.application.routes`
#
# What it lets through without an entry, because it is the pattern the layers
# use to talk upwards:
#
#   - a route NAME as a symbol (`:admin_page_path`): `Audit::Sentence::Route`
#     and `Jump::Search` hand the name and its arguments up, and a component
#     or view resolves it against a fixed list;
#   - a component CLASS handed to `RichText.component_renderer.call(...)` as
#     its argument. The model names which component draws a node and what it
#     is given; how a component becomes HTML (`ApplicationController.render`)
#     is the renderer's business, set in an initializer. The constant must be
#     the callable's argument: a component named anywhere else fails.
#
# Everything else that is allowed is in ALLOWED, with its reason, and an entry
# that no longer matches anything fails the test, so the list can't rot.
class DependencyDirectionTest < ActiveSupport::TestCase
  ROOTS = %w[app/models app/queries app/services].freeze

  COMPONENT = /(?:\b[A-Z]\w*::)*\b[A-Z]\w*Component\b/
  PATTERNS = {
    component: COMPONENT,
    application_controller: /\bApplicationController\b/,
    action_controller: /\bActionController\b(?:::Base\.helpers)?/,
    url_helpers: /\burl_helpers\b/,
    routes: /Rails\.application\.routes/
  }.freeze

  # The text before a constant that makes it a component class handed to the
  # renderer.
  RENDERER_ARGUMENT = /RichText\.component_renderer\.call\(\s*\z/

  # `pattern` is a key of PATTERNS; `matching` (optional) narrows the entry to
  # offences whose matched text fits it.
  ALLOWED = [
    { path: "app/models/content_types/*.rb", pattern: :component,
      reason: "a content type registers the components that render it (`t.list_component`, `t.detail_component`); the registration is the plugin seam" },
    { path: "app/models/block_types/*.rb", pattern: :component,
      reason: "a block type registers the component that renders it (`t.component`); the registration is the plugin seam" },
    { path: "app/models/rich_text/html_renderer.rb", pattern: :action_controller, matching: /\AActionController::Base\.helpers\z/,
      reason: "building HTML strings is this class's job, and Action View's tag helpers (`ActionController::Base.helpers`) are how; it renders no component and names no controller to do it" },
    { path: "app/models/rich_text/built_ins.rb", pattern: :action_controller, matching: /\AActionController::Base\.helpers\z/,
      reason: "the node and mark renderers build HTML strings with Action View's tag helpers (`ActionController::Base.helpers`); components go through `RichText.component_renderer`" },
    { path: "app/models/media/asset.rb", pattern: :url_helpers,
      reason: "`url`, `src` and `srcset` address a stored file or one of its variants through Active Storage's own URL helpers, which need the attachment object itself; they are not application routes a screen could name" },
    { path: "app/models/media/asset.rb", pattern: :routes,
      reason: "`Rails.application.routes.url_helpers` is how Active Storage's blob and representation paths are reached from a model; see the `url_helpers` entry" }
  ].freeze

  # A path and its offences, as "relative/path:line: pattern: matched text".
  def self.offences(path, source)
    code = without_comments(source)
    relative = path.to_s.delete_prefix("#{Rails.root}/")
    PATTERNS.flat_map do |name, pattern|
      code.to_enum(:scan, pattern).map { Regexp.last_match }.filter_map do |match|
        next if name == :component && code[0...match.begin(0)].match?(RENDERER_ARGUMENT)

        { path: relative, line: code[0...match.begin(0)].count("\n") + 1, pattern: name, text: match[0] }
      end
    end
  end

  # The source with every comment (a `#` line or tail, an `=begin` block)
  # blanked and the line breaks kept, so a line number still names the line.
  # Ripper does the lexing, so a `#` inside a string or an interpolation is
  # not mistaken for a comment.
  def self.without_comments(source)
    Ripper.lex(source).map do |(_position, type, token, _state)|
      type.to_s.match?(/\Aon_(comment|embdoc)/) ? token.gsub(/[^\n]/, "") : token
    end.join
  end

  def self.allowed?(offence, entry)
    File.fnmatch?(entry[:path], offence[:path], File::FNM_PATHNAME) &&
      entry[:pattern] == offence[:pattern] &&
      (entry[:matching].nil? || offence[:text].match?(entry[:matching]))
  end

  def sources = ROOTS.flat_map { |root| Dir[Rails.root.join(root, "**/*.rb")] }.sort

  def all_offences = sources.flat_map { |path| self.class.offences(path, File.read(path)) }

  test "the guard is looking at the code" do
    assert_operator sources.size, :>, 100, "this guard is looking at too little"
  end

  test "models, queries and services reach into no component, controller or route" do
    offending = all_offences.reject { |offence| ALLOWED.any? { |entry| self.class.allowed?(offence, entry) } }

    assert_empty offending.map { |offence| "#{offence[:path]}:#{offence[:line]}: #{offence[:pattern]}: #{offence[:text]}" },
      "a model, query or service names a component, a controller or the routes (CLAUDE.md, Dependency order). " \
      "Hand data or a route name up instead, or inject a callable; allow it in ALLOWED only with its reason."
  end

  test "every allowance still matches something" do
    offences = all_offences
    stale = ALLOWED.reject { |entry| offences.any? { |offence| self.class.allowed?(offence, entry) } }

    assert_empty stale.map { |entry| "#{entry[:path]} (#{entry[:pattern]})" }, "an ALLOWED entry no longer matches anything: delete it"
  end

  test "every allowance says why" do
    ALLOWED.each { |entry| assert_operator entry[:reason].length, :>, 40, "#{entry[:path]} needs its reason written out" }
  end

  test "the patterns match what they should, and nothing that only looks like it" do
    flagged = ->(source) { self.class.offences("app/models/x.rb", source).map { |offence| offence[:pattern] } }

    assert_equal [ :component ], flagged.call("Foo::BarComponent.new")
    assert_equal [ :component ], flagged.call("x = Admin::Foo::BarComponent")
    assert_equal [ :application_controller ], flagged.call("ApplicationController.render(x)")
    assert_equal [ :action_controller ], flagged.call("ActionController::Base.helpers")
    assert_equal [ :url_helpers ], flagged.call("Rails.application.routes.url_helpers.admin_page_path(1)").intersection([ :url_helpers ])
    assert_includes flagged.call("Rails.application.routes.url_helpers"), :routes

    assert_empty flagged.call("# Foo::BarComponent, ApplicationController, url_helpers\nx = 1 # ActionController")
    assert_empty flagged.call("=begin\nApplicationController\n=end\nx = 1")
    assert_empty flagged.call("Route.new(:admin_page_path, [ 1 ], {})")
    assert_empty flagged.call("RichText.component_renderer.call(Foo::BarComponent.new(id: 1))")
    assert_empty flagged.call("RichText.component_renderer.call(\n  Foo::BarComponent.new(id: 1)\n)")
    assert_equal [ :component ], flagged.call("render(Foo::BarComponent.new)")
    assert_equal [ :component ], flagged.call("RichText.component_renderer.call(x)\nFoo::BarComponent.new")
  end

  test "a line number names the line of the offence" do
    offence = self.class.offences("app/models/x.rb", "# a comment\n=begin\nnothing\n=end\n\nApplicationController\n").first

    assert_equal 6, offence[:line]
  end
end
