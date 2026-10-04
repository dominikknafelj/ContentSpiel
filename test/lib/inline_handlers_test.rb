require "test_helper"

# A strict Content-Security-Policy refuses inline event handlers, and they
# hide behaviour from the Stimulus controllers that own it. Dialogs open
# through `data-action="admin--dialog#open"` (see `dialog_trigger`).
class InlineHandlersTest < ActiveSupport::TestCase
  test "no view or component uses an inline event handler" do
    offenders = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{erb,rb}")].select do |path|
      File.read(path).match?(/["']?\bon(click|change|submit|input|key\w+|mouse\w+|focus|blur|load|error)\b["']?\s*(=>|[:=])/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end
end
