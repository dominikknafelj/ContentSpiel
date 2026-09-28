# Asserts on the content of one `<turbo-stream target="...">` in a Turbo
# Stream response -- an autosave answers with a stream per field slot
# (`Admin::AutosaveResponses#autosave_stream`), and a plain
# `assert_includes response.body` can't tell *which* slot a message landed
# in.
module TurboStreamTestHelper
  def assert_select_in_stream(target, pattern)
    stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='#{target}']")
    assert stream, "expected a turbo-stream targeting #{target.inspect} in:\n#{response.body}"
    assert_match pattern, stream.text
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include TurboStreamTestHelper
end
