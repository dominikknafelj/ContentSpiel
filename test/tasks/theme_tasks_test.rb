require "test_helper"
require "rake"
require "open3"
require "shellwords"

# `theme:new` and `theme:check` (lib/tasks/theme.rake): what a person types
# and what they are told. The work itself is Theme::Scaffold's and
# Theme::Check's, each with its own tests.
class ThemeTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("theme:check")
    @new = Rake::Task["theme:new"]
    @check = Rake::Task["theme:check"]
    [ @new, @check ].each(&:reenable)
  end

  test "theme:new writes the folder and says what to do next" do
    Dir.mktmpdir("theme") do |dir|
      target = File.join(dir, "site-theme")

      output = capture_io { @new.invoke(target) }.first

      assert File.file?(File.join(target, "views/pages/show.html.erb"))
      assert_includes output, target
      assert_includes output, "THEME_PATH=#{target} bin/dev", "the next step is the command that also builds the stylesheet"
    end
  end

  # An integrator exports THEME_PATH once, for the folder they are about to
  # make. The application does not start under a path that names no
  # directory, so as a prerequisite the boot ended this command with rake's
  # trace before it wrote anything.
  test "theme:new runs under a THEME_PATH that names the folder it is about to make" do
    Dir.mktmpdir("theme") do |dir|
      target = File.join(dir, "site-theme")

      printed, status = run_task("theme:new[#{target}]", "THEME_PATH" => target)

      assert_equal 0, status.exitstatus, printed
      assert File.file?(File.join(target, "views/pages/show.html.erb")), printed
      assert_includes printed, "THEME_PATH names no folder yet and is not read by this command"
      assert_no_match(/aborted!|ThemeFolder::Invalid|\.rb:\d+:in/, printed)
    end
  end

  test "theme:new without a path, and into a folder that is not empty, stops with a sentence and writes nothing" do
    _, said = capture_io { assert_raises(SystemExit) { @new.invoke } }
    assert_includes said, "bin/rails 'theme:new[PATH]'"

    with_theme_copy do |dir|
      @new.reenable
      before = Dir.glob("#{dir}/**/*").sort
      _, said = capture_io { assert_raises(SystemExit) { @new.invoke(dir.to_s) } }

      assert_includes said, "is not empty"
      assert_equal before, Dir.glob("#{dir}/**/*").sort
    end
  end

  # Rake cuts a task's arguments at every comma and trims around them, so a
  # path with one cannot be given in the brackets: `[/a b/c, d/theme]` was
  # written into `/a b/c`. Each task takes such a path from a variable, and
  # says so instead of using half a path.
  test "a path with a comma is refused in the brackets with the way to give it, and taken from THEME_NEW_PATH" do
    Dir.mktmpdir("theme") do |dir|
      _, said = capture_io { assert_raises(SystemExit) { @new.invoke(File.join(dir, "a"), "b") } }

      assert_includes said, "THEME_NEW_PATH"
      assert_includes said, "comma"
      assert_empty Dir.children(dir), "half a path is not written into"

      target = File.join(dir, "our site, v2", "theme")
      @new.reenable
      output = with_env("THEME_NEW_PATH" => target) { capture_io { @new.invoke }.first }

      assert File.file?(File.join(target, "views/pages/show.html.erb"))
      assert_includes output, "THEME_PATH=#{Shellwords.escape(target)}", "the next step pastes into a shell"
      assert_equal [ "THEME_PATH=#{target}", "bin/dev" ], Shellwords.split(output[/THEME_PATH=.*?(?= and it is drawn)/])

      @check.reenable
      _, said = capture_io { assert_raises(SystemExit) { @check.invoke(File.join(dir, "a"), "b") } }
      assert_includes said, "comma"
      assert_includes said, "THEME_PATH="
    end
  end

  # With the path given, the application is started under THEME_PATH's
  # folder all the same, and a refusal of THAT folder is kept for the length
  # of the task (`ThemeFolder.checking`). Saying nothing of it and ending 0
  # would call a process sound whose every public page raises.
  test "theme:check of a path while the theme the application started under is refused says so and ends 1" do
    refused = Theme.new(refusal: ThemeFolder::Invalid.new("THEME_PATH (/srv/other) is not a theme this version can draw"))

    status = nil
    out, said = Theme.with(refused) do
      capture_io { status = assert_raises(SystemExit) { @check.invoke(ThemeTestHelper::PLAIN.to_s) }.status }
    end

    assert_equal 1, status
    assert_match(/#{Regexp.escape(ThemeTestHelper::PLAIN.to_s)}: \d+ templates, no problems\./, out)
    assert_includes said, "THEME_PATH names another folder, which was NOT checked here and is refused"
    assert_includes said, "bin/rails theme:check"
  end

  # N1 of the re-review: with THEME_PATH=x refused and `theme:check[x]`, the
  # whole list for x was printed and then "names another folder, which was
  # NOT checked". It was checked.
  test "theme:check of the very folder the application started under does not say that another folder was not checked" do
    with_theme_copy do |dir|
      dir.join("views/pages/shwo.html.erb").write("x")
      started = ThemeFolder.new(dir)
      refused = Theme.prepare(started, reload: true)
      assert refused.refusal

      [ dir.to_s, "#{dir}/", File.join(dir, "views", "..") ].each do |argument|
        @check.reenable
        status = nil
        _, said = with_singleton_override(ThemeFolder, :current, -> { started }) do
          Theme.with(refused) { capture_io { status = assert_raises(SystemExit) { @check.invoke(argument) }.status } }
        end

        assert_equal 1, status
        assert_includes said, "views/pages/shwo.html.erb is not part of the theme contract"
        assert_includes said, "1 problem."
        assert_not_includes said, "NOT checked", argument
      end
    end
  end

  # N2: a variable left in a shell from the last run names a folder nobody
  # is thinking of. The task says where it took the path from before it
  # writes anything.
  test "theme:new says, before it writes, that the path is THEME_NEW_PATH's, and says nothing of it for a path in the brackets" do
    Dir.mktmpdir("theme") do |dir|
      target = File.join(dir, "from-the-variable")
      output = with_env("THEME_NEW_PATH" => target) { capture_io { @new.invoke }.first }

      assert_equal "The path is THEME_NEW_PATH's: #{target}", output.lines.first.chomp
      assert_operator output.index("THEME_NEW_PATH's"), :<, output.index("Wrote ")

      @new.reenable
      File.write(File.join(target, "views/pages/show.html.erb"), "changed")
      said = with_env("THEME_NEW_PATH" => target) { capture_io { assert_raises(SystemExit) { @new.invoke } } }
      assert_includes said.first, "The path is THEME_NEW_PATH's: #{target}", "said also when the folder is then refused"
      assert_includes said.last, "is not empty"

      @new.reenable
      other = File.join(dir, "in-the-brackets")
      output = with_env("THEME_NEW_PATH" => target) { capture_io { @new.invoke(other) }.first }
      assert_not_includes output, "THEME_NEW_PATH"
      assert File.file?(File.join(other, "views/pages/show.html.erb"))
    end
  end

  test "theme:check of a sound folder says so and how many templates it has" do
    output = capture_io { @check.invoke(ThemeTestHelper::PLAIN.to_s) }.first

    assert_includes output, ThemeTestHelper::PLAIN.to_s
    assert_match(/\d+ templates, no problems/, output)
  end

  test "theme:check names every problem, the deep ones too, and exits 1" do
    with_theme_copy do |dir|
      dir.join("views/pages/shwo.html.erb").write("x")
      dir.join("views/theme/_broken.html.erb").write("<% if true %>\n")
      dir.join("views/theme/_asks.html.erb").write("<%= params[:q] %>\n")

      status = nil
      _, said = capture_io { status = assert_raises(SystemExit) { @check.invoke(dir.to_s) }.status }

      assert_equal 1, status
      assert_includes said, "views/pages/shwo.html.erb is not part of the theme contract"
      assert_includes said, "views/theme/_broken.html.erb does not compile"
      assert_includes said, "views/theme/_asks.html.erb reads params"
      assert_includes said, "3 problems"
    end
  end

  # The form a site's image build runs: no argument, THEME_PATH set by the
  # Dockerfile, production, no secret. Under a folder the application does
  # not START under (Theme.load refuses it when the application is
  # prepared), the task used to be never reached: the build's log ended in
  # rake's "aborted!", the exception's class and a trace, and named the
  # boot's problems only, so a template that does not compile came to light
  # one build later. One real boot, about three seconds.
  test "theme:check under a THEME_PATH the application does not start under names every problem, the deep ones too, with no trace" do
    with_theme_copy do |dir|
      dir.join("views/pages/shwo.html.erb").write("x")
      dir.join("views/theme/_broken.html.erb").write("<% if true %>\n")

      printed, status = run_task("theme:check", "THEME_PATH" => dir.to_s)

      assert_equal 1, status.exitstatus, printed
      assert_includes printed, "views/pages/shwo.html.erb is not part of the theme contract"
      assert_includes printed, "views/theme/_broken.html.erb does not compile"
      assert_includes printed, "#{dir}: 2 problems."
      assert_no_match(/aborted!|ThemeFolder::Invalid|\.rb:\d+:in|--trace/, printed)
      assert_equal 1, printed.scan("shwo.html.erb").size, "said once: the boot's own log line is not printed beside the list"
    end
  end

  test "theme:check with no path and no THEME_PATH says which to give, and a path that is no folder says so" do
    _, said = capture_io { assert_raises(SystemExit) { @check.invoke } }
    assert_includes said, "set THEME_PATH or run bin/rails 'theme:check[PATH]'"

    @check.reenable
    _, said = capture_io { assert_raises(SystemExit) { @check.invoke("/no/such/theme/anywhere") } }
    assert_includes said, "THEME_PATH names no directory: /no/such/theme/anywhere"
  end

  private
    BOOT_SECONDS = 90

    def with_env(variables)
      before = variables.keys.index_with { |name| ENV[name] }
      variables.each { |name, value| ENV[name] = value }
      yield
    ensure
      before.each { |name, value| ENV[name] = value }
    end

    # A task in a process of its own, started as the image build starts it
    # (`test/lib/production_boot_test.rb` says why no database is asked and
    # which variables are taken away). What it printed, both streams, and
    # how it ended.
    def run_task(*command, **variables)
      env = {
        "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1",
        "PUBLIC_HOST" => nil, "SITEMAP_HOST" => nil, "THEME_PATH" => nil, "ASSUME_SSL" => nil, "RAILS_LOG_LEVEL" => nil,
        "SECRET_KEY_BASE" => nil, "RAILS_MASTER_KEY" => nil, "DATABASE_URL" => nil, "ADMIN_PATH" => nil,
        "OTEL_EXPORTER_OTLP_ENDPOINT" => nil, "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => nil, "OTEL_CONSOLE" => nil
      }.merge(variables.transform_keys(&:to_s))

      Bundler.with_original_env do
        Open3.popen2e(env, Rails.root.join("bin/rails").to_s, *command, chdir: Rails.root.to_s) do |input, output, thread|
          input.close
          reader = Thread.new { output.read }

          unless thread.join(BOOT_SECONDS)
            Process.kill("KILL", thread.pid)
            thread.join
            flunk "#{command.join(" ")} did not finish in #{BOOT_SECONDS} seconds"
          end

          [ reader.value, thread.value ]
        end
      end
    end
end
