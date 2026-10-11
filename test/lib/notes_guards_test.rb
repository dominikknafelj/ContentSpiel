require "test_helper"

# Three rules of notes that nothing else fails on when they are broken
# (CLAUDE.md, "Rules a change can break silently"; `docs/reference/notes.md`
# has the incidents behind them). Source scans, like
# `test/services/service_contract_test.rb`: tripwires for the change that
# never thought about the rule, not proofs of behaviour -- those are the
# tests each rule names beside these.
class NotesGuardsTest < ActiveSupport::TestCase
  def self.relative(file) = Pathname(file).relative_path_from(Rails.root).to_s

  # --- 1. no page refresh, no morphing (decision D20) -------------------------
  #
  # The write queue serialises every write of an autosave screen on the
  # assumption that Turbo never redraws the page under an open form, and live
  # delivery refreshes notes part by part for the same reason. Each of these
  # switches a page refresh on, or sends one: named anywhere in the app --
  # code, markup, a script or a comment that could be uncommented -- it fails.
  # (Any OTHER broadcast is refused by `test/models/notes/signals_test.rb`,
  # "nothing in the app broadcasts but Live::Signals, ...".)
  # A refresh sent as a stream is one too: `turbo_stream.refresh`, or the
  # element it writes.
  MORPHING = /turbo_refreshes_with|turbo_refresh_method_tag|turbo_refresh_scroll_tag|turbo-refresh-method|turbo-refresh-scroll|broadcasts?_refresh|turbo_stream\.refresh\b(?!_)|turbo_stream_refresh_tag|<turbo-stream[^>]*action=["']refresh/

  test "nothing in the app turns on Turbo's page refresh or morphing, or broadcasts one" do
    files = Dir[Rails.root.join("{app,config,lib}/**/*.{rb,erb,js,yml,html}")]
    assert_operator files.size, :>, 300, "the scan found too few files to mean anything"

    found = files.select { |file| File.read(file).match?(MORPHING) }

    assert_empty found.map { |file| self.class.relative(file) }
  end

  test "the morphing scan sees each of the ways to switch it on" do
    [ %(<%= turbo_refreshes_with method: :morph, scroll: :preserve %>), %(<meta name="turbo-refresh-method" content="morph">),
      %(<meta name="turbo-refresh-scroll" content="preserve">), "broadcast_refresh_to(page)", "broadcasts_refreshes", "broadcast_refresh_later",
      "turbo_refresh_method_tag(:morph)", "render turbo_stream: turbo_stream.refresh(request_id: nil)", "turbo_stream_refresh_tag",
      %(<turbo-stream request-id="x" action="refresh"></turbo-stream>) ].each do |line|
      assert_match MORPHING, line
    end
    assert_no_match MORPHING, %(frame.reload() // refresh the frame, turbo_stream.replace)
    assert_no_match MORPHING, %(<turbo-stream action="replace" target="x"></turbo-stream> turbo_stream.refresh_counts)
  end

  # --- 2. the container's row lock first --------------------------------------
  #
  # Every notes service takes the container's row lock as the first statement
  # of its transaction (`Notes::Authorization#lock_container`, or
  # `with_locked_thread`, which calls it): the same first lock a page's block
  # writes take, so a note and a delete run one after the other. A service
  # that takes none says why in its class body:
  #
  #   # lock: none (reason)
  #
  # The ORDER of the statements is pinned by the `capture_sql` tests
  # (`test/services/notes/thread_state_test.rb` and its neighbours); this only
  # catches the new service that has neither the call nor the sentence.
  LOCK_EXEMPTION = /^\s*# lock: none \(.{10,}\)/
  LOCK_CALL = /\b(lock_container|with_locked_thread)\(/

  def self.notes_services = Dir[Rails.root.join("app/services/notes/*.rb")].reject { |file| File.basename(file) == "authorization.rb" }

  # The lines of `class <name> ...` through its closing `end`: the class body
  # an exemption must sit in, not a doc comment above it
  # (`ServiceContractTest.class_body`, whose rule this is).
  def self.class_body(source, name)
    lines = source.lines
    start = lines.index { |line| line.match?(/^\s*class #{Regexp.escape(name)}\b/) } or return
    indent = lines[start][/\A\s*/]
    finish = (start + 1...lines.size).find { |index| lines[index].chomp == "#{indent}end" }
    lines[start..finish].join
  end

  # The code of a source, without its comments.
  def self.code(source) = source.lines.reject { |line| line.strip.start_with?("#") }.join

  test "every notes service takes the container's lock, or says in its class body why it takes none" do
    services = self.class.notes_services
    assert_operator services.size, :>=, 12

    missing = services.reject do |file|
      source = File.read(file)
      body = self.class.class_body(source, File.basename(file, ".rb").camelize) or flunk("no class in #{self.class.relative(file)}")
      self.class.code(body).match?(LOCK_CALL) || body.match?(LOCK_EXEMPTION)
    end

    assert_empty missing.map { |file| self.class.relative(file) }, "a notes service without lock_container( / with_locked_thread( and without `# lock: none (reason)`"
  end

  test "the lock scan is not satisfied by a comment that names the call, nor by an exemption without a reason" do
    assert_no_match LOCK_CALL, self.class.code("  # the caller holds it (`lock_container(page)`)\n  def call = write\n")
    assert_match LOCK_CALL, self.class.code("  def call = lock_container(container) && write\n")
    assert_no_match LOCK_EXEMPTION, "    # lock: none\n"
    assert_no_match LOCK_EXEMPTION, "    # lock: none (n/a)\n"
    assert_match LOCK_EXEMPTION, "    # lock: none (its callers hold the row already)\n"
  end

  # --- 3. no link into the notes frame is prefetched ---------------------------
  #
  # Opening a thread marks it read, so its GET must be made by nobody but a
  # person opening it; and a prefetch once cost an open edit its text (the
  # frame merge took it for the frame's own navigation). Prefetch is on in CS
  # Studio, and only the editors and the Media screen switch it off for the
  # whole page: on a record's notes page the attribute on the link is all
  # there is. So wherever a notes template or component names the notes frame
  # as a link's target, the same line says `turbo_prefetch: false`
  # (`data-turbo-prefetch="false"` in plain markup). A FORM that names the
  # frame is not a link, and is not prefetched: `form_with`, `button_to`, a
  # `form:` option, and the two methods that hold a form's data.
  FRAME = /turbo_frame: ["':]notes|data-turbo-frame=["']notes|"turbo-frame" => "notes"/
  NO_PREFETCH = /turbo_prefetch: false|data-turbo-prefetch=["']false/
  FORM = /\bform_with\b|\bbutton_to\b|\bform: \{|def frame_form\b|def form_data\b/

  def self.frame_sources = Dir[Rails.root.join("app/components/admin/notes_screen/**/*.{rb,erb}"), Rails.root.join("app/views/admin/note*/**/*.erb")]

  # The lines that name the notes frame for something that is not a form and
  # do not switch prefetch off. A form's data may stand on the line after
  # the one that says it is a form's.
  def self.prefetched(source)
    lines = source.lines
    lines.each_index.select do |index|
      line = lines[index]
      line.match?(FRAME) && !line.match?(NO_PREFETCH) && !line.match?(FORM) && !(index.positive? && lines[index - 1].match?(FORM))
    end.map { |index| index + 1 }
  end

  test "every link into the notes frame switches prefetch off" do
    sources = self.class.frame_sources
    assert_operator sources.size, :>, 20
    assert_operator sources.sum { |file| File.read(file).scan(NO_PREFETCH).size }, :>=, 6, "the scan no longer finds the links it is about"

    found = sources.flat_map { |file| self.class.prefetched(File.read(file)).map { |line| "#{self.class.relative(file)}:#{line}" } }

    assert_empty found, "a link into turbo-frame#notes without turbo_prefetch: false"
  end

  test "the prefetch scan tells a link from a form" do
    assert_equal [ 1 ], self.class.prefetched(%(<%= link_to "Open", path, data: { turbo_frame: "notes" } %>\n))
    assert_equal [ 1 ], self.class.prefetched(%(<a href="/x" data-turbo-frame="notes">Open</a>\n))
    assert_empty self.class.prefetched(%(<%= link_to "Open", path, data: { turbo_frame: "notes", turbo_prefetch: false } %>\n))
    assert_empty self.class.prefetched(%(<a href="/x" data-turbo-frame="notes" data-turbo-prefetch="false">Open</a>\n))
    assert_empty self.class.prefetched(%(<%= form_with url: path, data: { turbo_frame: "notes" } do %>\n))
    assert_empty self.class.prefetched(%(<%= button_to "Pin", path, form: { data: { turbo_frame: "notes" } } %>\n))
    assert_empty self.class.prefetched(%(def form_data\n  { controller: "x", turbo_frame: "notes" }\nend\n))
  end
end
