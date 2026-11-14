require "test_helper"

# Every message a script asks for is one the server serves. A script's
# `messages(element).t("components.ui.save_bar.blocked")` throws when no
# `data-messages` up to <body> has the key (`i18n/messages.js`), and a path no
# test walks would ship that throw. So this reads the script sources for
# every string literal that is a message key -- one whose first segment is a
# top-level key under `admin` in the locale files -- and checks it is in a list
# a `messages_data` call renders: `Admin::MessagesHelper::SCRIPT_MESSAGES` (the
# set on <body>), the literal arguments of a `messages_data(...)` call in a
# view or component, or a constant list splatted into one (namespaced, or a
# constant of the file's own class); or that a component hands its script
# beside one (`SENTENCES`, below). A `${...}` in the script's key stands for one segment
# and is served if any served key fits it, a `#{...}` in the server's for a
# placeholder (`components.ui.chip_input.nouns.#{noun}.create`).
class ScriptMessagesTest < ActiveSupport::TestCase
  SCRIPTS = Dir[Rails.root.join("app/javascript/**/*.js")].reject { |path| path.include?("/javascript/i18n/") }
  KEY = /(?<=["`'])(?:#{I18n.t("admin").keys.map { |key| Regexp.escape(key.to_s) }.join("|")})\.[\w.${}]+(?=["`'])/

  # What a message key looks like: dotted lower-case segments, a `${...}` for
  # one of them. Every literal handed to `.t(` or `this.text(` has to be one,
  # whatever its first segment, so a mistyped prefix is caught here rather
  # than found by the one test that walks the path.
  SHAPE = /\A[a-z_]+(?:\.(?:[a-z_]+|\$\{[^}]*\}))+\z/
  ASKED = /(?:\.t|this\.text)\(\s*(["'`])(.*?)\1/

  def script_keys
    SCRIPTS.flat_map do |path|
      source = File.read(path)
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      (source.scan(KEY) + source.scan(ASKED).map(&:last)).map { |key| [ key, relative ] }
    end.uniq
  end

  def served
    calls = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{rb,erb}")].flat_map do |path|
      source = File.read(path).lines.reject { |line| line.match?(/\A\s*#/) }.join.gsub(/<%#.*?%>/m, "")
      source.scan(/messages_data\((.*?)\)(?=\s*(?:%>|\n|\)|,))/m).flatten.map { |call| [ call, path ] }
    end
    literals = calls.flat_map { |call, _path| call.scan(/"([^"]+)"/).flatten }
    # A list handed over whole, `messages_data(*Admin::Ui::NewRecordDialogComponent::MESSAGES)`,
    # or a constant of the file's own class, `messages_data(*SCRIPT_MESSAGES)`.
    splats = calls.flat_map do |call, path|
      call.scan(/\*((?:[A-Z]\w*::)*[A-Z][A-Z0-9_]+)\b/).flatten.flat_map do |name|
        owner = name.include?("::") ? Object : Rails.autoloaders.main.cpath_expected_at(path)&.constantize
        owner ? owner.const_get(name) : []
      end
    end
    (Admin::MessagesHelper::SCRIPT_MESSAGES + literals + splats + sentences.keys).map { |key| key.gsub(/#\{.*?\}/, "x") }
  end

  # A string from outside `admin` that a component hands its script under a
  # key of its own, beside `messages_data` (`Admin::Fields::MermaidField`'s
  # refusal sentences, `errors.messages.diagram_*`): a component's `SENTENCES`
  # constant, the script's key => the I18n key whose string it is.
  def sentences
    Dir[Rails.root.join("app/components/**/*.rb")].select { |path| File.read(path).match?(/^\s*SENTENCES = /) }.map do |path|
      Rails.autoloaders.main.cpath_expected_at(path).constantize.const_get(:SENTENCES, false)
    end.reduce({}, :merge)
  end

  test "the scripts ask for keys, and for each the server serves it" do
    keys = script_keys
    assert_operator keys.size, :>, 25, "the sources moved: this guard is looking at too little"

    served_keys = served
    unserved = keys.reject do |key, _path|
      asked = Regexp.new("\\A#{Regexp.escape(key).gsub(/\\\$\\\{.*?\\\}/, "[^.]+")}\\z")
      served_keys.any? { |served_key| asked.match?(served_key) }
    end
    assert_empty unserved, "No messages_data call serves these (add the key to the element's data-messages):\n#{unserved.map { |key, path| "#{path}: #{key}" }.join("\n")}"
  end

  test "every literal handed to t( or this.text( has the shape of a key" do
    odd = script_keys.reject { |key, _path| key.match?(SHAPE) }

    assert_empty odd, "Not a message key (dotted lower-case segments):\n#{odd.map { |key, path| "#{path}: #{key}" }.join("\n")}"
  end

  test "every served key exists in the locale files" do
    Admin::MessagesHelper::SCRIPT_MESSAGES.each { |key| assert I18n.exists?("admin.#{key}"), key }
  end

  test "a component's sentences are read, and each names a string that exists" do
    served_sentences = sentences
    assert_includes served_sentences.keys, "components.fields.mermaid_field.refused.colours", "the guard no longer reads MermaidField's sentences"
    served_sentences.each { |key, sentence| assert I18n.exists?(sentence), "#{key}: #{sentence}" }
  end
end
