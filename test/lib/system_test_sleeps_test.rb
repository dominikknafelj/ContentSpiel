require "test_helper"

# No fixed sleeps in system tests. A `sleep` waits a guessed time: too short
# and the test flakes, too long and every run pays for it, and an absence
# ("nothing was sent") that rests on one proves nothing about what happened
# after it. A test waits for a condition instead -- a waiting Capybara
# assertion, `assert_eventually`, `await_js`, `click_frame_link`, or for the
# write queue (`assert_writes_settled`), a held request the test releases, a
# page that has run its frames (`await_frames`) -- and where nothing marks the
# end of the window, a sleep stays at the shortest length that covers the
# mechanism, and says which one on its own line:
#
#   sleep 1.1 # sleep: the autosave debounce is 1 s; nothing marks its expiry when nothing is sent
#
# The reason is the text after `# sleep:` on the same line, ten characters at
# least.
class SystemTestSleepsTest < ActiveSupport::TestCase
  # `sleep` as a statement or a call -- at the start of a line (a statement,
  # `sleep 0.5 until ...`) or after anything that isn't a word character or a
  # dot (`Timeout.timeout(5) { sleep 0.05 ... }`, `(sleep 1)`, `x; sleep(2)`),
  # followed by a number or a parenthesis or a variable. A method that merely
  # has the word in its name (`await_sleep`, `obj.sleep`, `sleeping`) isn't one,
  # nor is a word in a comment or in a string.
  #
  # `Kernel.sleep`, `::Kernel.sleep` and `Kernel::sleep` are flagged too.
  # Deliberately NOT caught: `send(:sleep, 1)` / `public_send` and a bare
  # `sleep` with no argument inside a block (`loop { sleep }`) -- nothing in
  # the system tests spells it so, and a regex over lines can't tell them from
  # prose.
  SLEEP = /^\s*sleep\b|[^.\w:]sleep\s*[\d(\w]|(?<![\w])(?:::)?Kernel(?:\.|::)sleep\b/
  REASON = /# sleep:\s*\S.{9,}/

  # The code of a line: what is left once a string's content and a trailing
  # comment are taken out, so `setTimeout(...)` in a heredoc line, a "sleep"
  # in a message or a comment saying `sleep` can't match. Heredoc bodies are
  # skipped as strings whole (JavaScript has no `sleep`, and the Ruby around
  # it is checked line by line).
  def code_lines(path)
    in_heredoc = nil
    File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
      if in_heredoc
        in_heredoc = nil if line.strip == in_heredoc
        next
      end
      # A heredoc opener names an UPPERCASE or quoted tag (`<<~JS`, `<<~'RUBY'`): `list <<item` is an append.
      if (opener = line.match(/<<[~-]?(?:(["'])(\w+)\1|([A-Z][A-Z0-9_]*))/))
        in_heredoc = opener[2] || opener[3]
      end
      code = line.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, '""')
      code = code.sub(/\s#(?!\{).*\z/, "") unless code.strip.start_with?("#")
      next if code.strip.start_with?("#")

      [ index + 1, line, code ]
    end
  end

  def offences
    paths = Dir[Rails.root.join("test/system/**/*.rb"), Rails.root.join("test/application_system_test_case.rb")]
    assert_operator paths.size, :>, 20, "the sources moved: this guard is looking at too little"
    paths.flat_map do |path|
      code_lines(path).filter_map do |number, line, code|
        next unless code.match?(SLEEP)
        next if line.match?(REASON)

        "#{Pathname(path).relative_path_from(Rails.root)}:#{number}: #{line.strip}"
      end
    end
  end

  test "every sleep in a system test carries a reason" do
    assert_empty offences, "a sleep needs `# sleep: <why nothing can be waited for instead>` on its line (see this file)"
  end

  # The guard is only worth having if it catches what it claims to and
  # nothing else.
  test "the pattern finds sleeps, and nothing that only looks like one" do
    [ "    sleep 0.3", "  sleep(0.5)", "sleep 1", "    sleep 0.05 until done", "Timeout.timeout(5) { sleep 0.05 until x }",
      "loop { sleep 0.1 }", "x = 1; sleep(2)", "      sleep delay if delay.positive?", "sleep(self.class.delay.to_f)",
      "Kernel.sleep 1", "Kernel.sleep(1)", "::Kernel.sleep 1", "Kernel::sleep 1" ].each do |sample|
      assert_match SLEEP, sample
    end
    [ "await_sleep 1", "obj.sleep 1", "sleeping = true", "setTimeout(poll, 20)", "# sleep 1", "Kernel::sleeper" ].each do |sample|
      assert_no_match SLEEP, sample.sub(/\A\s*#.*/, "")
    end
  end

  test "comments, strings and heredoc bodies are not code" do
    Tempfile.create([ "sleeps", ".rb" ]) do |file|
      file.write(<<~'RUBY')
        # sleep 1 in a comment
        message = "sleep 2 in a string"
        x = 1 # then sleep 1 later
        list <<item
        page.execute_script(<<~JS)
          setTimeout(() => sleep(3), 10)
          sleep 4
        JS
        sleep 5 # sleep: a reason long enough
        sleep 6 # no reason
        sleep 7 # sleep: nine chrs
        sleep 8 # sleep: ten chars!
      RUBY
      file.flush
      flagged = code_lines(file.path).select { |_, _, code| code.match?(SLEEP) }.map(&:first)
      assert_equal [ 9, 10, 11, 12 ], flagged
      assert_equal [ 10, 11 ], flagged.reject { |n| File.readlines(file.path)[n - 1].match?(REASON) }
    end
  end
end
