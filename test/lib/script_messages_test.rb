require "test_helper"

# Every message a script asks for is one the server serves. A script's
# `messages(element).t("components.save_bar.blocked")` throws when no
# `data-messages` up to <body> has the key (`i18n/messages.js`), and a path no
# test walks would ship that throw. So this reads the script sources for
# every string literal that is a message key -- one whose first segment is a
# top-level key under `admin` in the locale files -- and checks it is in a list
# a `messages_data` call renders: `Admin::MessagesHelper::SCRIPT_MESSAGES` (the
# set on <body>) or the literal arguments of a `messages_data(...)` call in a
# view or component. A `${...}` in the script's key stands for one segment
# and is served if any served key fits it, a `#{...}` in the server's for a
# placeholder (`components.chip_input.nouns.#{noun}.create`).
class ScriptMessagesTest < ActiveSupport::TestCase
  SCRIPTS = Dir[Rails.root.join("app/javascript/**/*.js")].reject { |path| path.include?("/javascript/i18n/") }
  KEY = /(?<=["`'])(?:#{I18n.t("admin").keys.map { |key| Regexp.escape(key.to_s) }.join("|")})\.[\w.${}]+(?=["`'])/

  def script_keys
    SCRIPTS.flat_map { |path| File.read(path).scan(KEY).map { |key| [ key, Pathname(path).relative_path_from(Rails.root).to_s ] } }.uniq
  end

  def served
    calls = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{rb,erb}")].flat_map do |path|
      File.read(path).scan(/messages_data\((.*?)\)(?=\s*(?:%>|\n|\)|,))/m).flatten
    end
    literals = calls.flat_map { |call| call.scan(/"([^"]+)"/).flatten }
    (Admin::MessagesHelper::SCRIPT_MESSAGES + literals).map { |key| key.gsub(/#\{.*?\}/, "x") }
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

  test "every served key exists in the locale files" do
    Admin::MessagesHelper::SCRIPT_MESSAGES.each { |key| assert I18n.exists?("admin.#{key}"), key }
  end
end
