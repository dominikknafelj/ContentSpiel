require "test_helper"

# An ERB comment (`<%# ... %>`) ends at the first `%>`, so a comment that
# quotes an output tag (`<%= x %>`) closes early and the rest of the
# comment renders as visible text -- which happened twice in CS Studio
# (the settings logo field and the audit event snapshot). Write such
# references as prose ("the output tag") instead.
class ErbCommentsTest < ActiveSupport::TestCase
  test "no ERB comment contains another ERB tag" do
    offenders = Dir[Rails.root.join("app/**/*.erb")].flat_map do |path|
      File.read(path).scan(/<%#(.*?)%>/m).filter_map do |(body)|
        "#{path.delete_prefix("#{Rails.root}/")}: #{body.strip.lines.first.strip}" if body.include?("<%")
      end
    end

    assert_empty offenders, "ERB comments that quote an ERB tag close early:\n#{offenders.join("\n")}"
  end
end
