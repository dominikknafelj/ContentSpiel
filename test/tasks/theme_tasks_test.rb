require "test_helper"
require "rake"
require "open3"

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
      assert_includes output, "THEME_PATH=#{target}"
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
