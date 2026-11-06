require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

# install/install.sh and install/contentspiel (the wrapper) are plain POSIX sh
# that a person runs on their own machine, so they are tested as they are run:
# in a throwaway folder, with a fake `docker` and `curl` first on PATH that
# write each call's arguments, one per line after a "CALL" line, to a file.
class InstallScriptsTest < ActiveSupport::TestCase
  ROOT = Rails.root
  WRAPPER = ROOT.join("install/contentspiel").to_s
  INSTALLER = ROOT.join("install/install.sh").to_s
  IMAGE = ContentSpiel::IMAGE

  FAKE_DOCKER = <<~SH.freeze
    #!/bin/sh
    { echo CALL; for a in "$@"; do printf '%s\\n' "$a"; done; echo "PWD=$(pwd)"; } >> "$FAKE_LOG"
    [ "$1" = version ] && [ -n "${FAKE_DOCKER_DOWN:-}" ] && exit 1
    exit 0
  SH

  # Writes what the installer would download, or fails the way `curl -f` does.
  FAKE_CURL = <<~SH.freeze
    #!/bin/sh
    { echo CURL; for a in "$@"; do printf '%s\\n' "$a"; done; } >> "$FAKE_LOG"
    [ -n "${FAKE_CURL_FAILS:-}" ] && exit 22
    out=""
    while [ $# -gt 0 ]; do
      [ "$1" = -o ] && out=$2
      shift
    done
    printf '#!/bin/sh\\necho downloaded\\n' > "$out"
  SH

  test "the wrapper's default image is the one the release workflow pushes" do
    assert_match(/^IMAGE=\$\{CONTENTSPIEL_IMAGE:-#{Regexp.escape(IMAGE)}\}$/, File.read(WRAPPER))
  end

  test "the version comes from the pin in the folder" do
    in_sandbox do |box|
      File.write("#{box.site}/.contentspiel-version", "0.3.1\nignored\n")
      box.wrap("pages", "list")

      assert_includes box.run_call.fetch(:args), "#{IMAGE}:0.3.1"
    end
  end

  test "the version comes from a pin in a parent folder, and that folder is the site" do
    in_sandbox do |box|
      File.write("#{box.site}/.contentspiel-version", "0.2.0\n")
      FileUtils.mkdir_p("#{box.site}/a/b")
      box.wrap("pages", chdir: "#{box.site}/a/b")
      args = box.run_call.fetch(:args)

      assert_includes args, "#{IMAGE}:0.2.0"
      assert_includes args, "type=bind,source=#{File.realpath(box.site)},target=/site"
    end
  end

  test "without a pin the version is stable and the site is the current folder" do
    in_sandbox do |box|
      box.wrap("pages")
      args = box.run_call.fetch(:args)

      assert_includes args, "#{IMAGE}:stable"
      assert_includes args, "type=bind,source=#{File.realpath(box.site)},target=/site"
    end
  end

  test "arguments reach the image unchanged, spaces, quotes and flags included" do
    in_sandbox do |box|
      given = [ "page", "new", "--title", "Hello  world", "it's \"quoted\"", "--flag=a b", "$HOME", "" ]
      box.wrap(*given)
      args = box.run_call.fetch(:args)

      assert_equal [ "contentspiel", *given ], args.drop(args.index("contentspiel"))
    end
  end

  test "the line carries the user's uid and gid, the site mount and the working folder" do
    in_sandbox do |box|
      box.wrap("pages")
      args = box.run_call.fetch(:args)
      uid, gid = `id -u`.strip, `id -g`.strip

      assert_equal %w[run --rm], args.first(2)
      assert_equal "#{uid}:#{gid}", args[args.index("--user") + 1]
      assert_equal "/site", args[args.index("-w") + 1]
      assert_equal "type=bind,source=#{File.realpath(box.site)},target=/site", args[args.index("--mount") + 1]
    end
  end

  test "a pin that is not X.Y.Z or stable is refused" do
    in_sandbox do |box|
      [ "latest", "1.2", "1.2.3-beta", "v1.2.3", "1.2.3.4", "@sha256:#{'a' * 64}", "../x", "1..2" ].each do |pin|
        File.write("#{box.site}/.contentspiel-version", "#{pin}\n")
        out, status = box.wrap_raw("pages")

        assert_equal 1, status.exitstatus, pin
        assert_includes out, ".contentspiel-version must hold X.Y.Z or stable"
      end
      assert_empty box.calls
    end
  end

  test "a pin of stable is accepted" do
    in_sandbox do |box|
      File.write("#{box.site}/.contentspiel-version", "stable\n")
      box.wrap("pages")

      assert_includes box.run_call.fetch(:args), "#{IMAGE}:stable"
    end
  end

  test "the wrapper without docker says to install it and exits 1" do
    in_sandbox do |box|
      out, status = Open3.capture2e(box.env("PATH" => "/usr/bin:/bin"), WRAPPER, "pages", chdir: box.site)

      assert_equal 1, status.exitstatus
      assert_match(/install docker/i, out)
    end
  end

  test "dev refuses extra arguments" do
    in_sandbox do |box|
      out, status = box.wrap_raw("dev", "--build")

      assert_equal 1, status.exitstatus
      assert_includes out, "dev takes no arguments"
      assert_empty box.calls
    end
  end

  test "a site path with a colon is mounted intact" do
    in_sandbox do |box|
      odd = "#{box.dir}/we:ird"
      FileUtils.mkdir_p(odd)
      box.wrap("pages", chdir: odd)

      assert_includes box.run_call.fetch(:args), "type=bind,source=#{odd},target=/site"
    end
  end

  test "install expands a leading ~/ in the bin folder" do
    in_sandbox do |box|
      status, = box.install("HOME" => box.dir, "CONTENTSPIEL_BIN_DIR" => "~/mybin")

      assert status.success?
      assert File.executable?("#{box.dir}/mybin/contentspiel")
    end
  end

  test "without a terminal there is no -t" do
    in_sandbox do |box|
      box.wrap("pages")

      assert_not_includes box.run_call.fetch(:args), "-t"
    end
  end

  test "dev runs dev-files in the image and then compose from the site folder" do
    in_sandbox do |box|
      File.write("#{box.site}/.contentspiel-version", "0.4.0\n")
      FileUtils.mkdir_p("#{box.site}/sub")
      box.wrap("dev", chdir: "#{box.site}/sub")
      calls = box.calls

      assert_equal 2, calls.size
      assert_includes calls[0][:args], "#{IMAGE}:0.4.0"
      assert_equal %w[contentspiel dev-files], calls[0][:args].last(2)
      assert_equal %w[compose -f .contentspiel/compose.yml up], calls[1][:args]
      assert_equal File.realpath(box.site), calls[1][:pwd]
    end
  end

  test "install with no Docker exits 1 and writes nothing" do
    in_sandbox do |box|
      status, out = box.install("FAKE_DOCKER_DOWN" => "1")

      assert_equal 1, status.exitstatus
      assert_match(/docker/i, out)
      assert_empty Dir.children(box.bin)
      assert_not_includes File.read(box.log), "CURL"
    end
  end

  test "install with Docker writes an executable wrapper" do
    in_sandbox do |box|
      status, = box.install
      target = "#{box.bin}/contentspiel"

      assert status.success?
      assert File.executable?(target)
      assert_match(/downloaded/, File.read(target))
      assert_equal [ "contentspiel" ], Dir.children(box.bin), "no temp file is left behind"
      assert_includes File.read(box.log), "https://example.test/contentspiel"
    end
  end

  test "a failed download writes nothing" do
    in_sandbox do |box|
      status, = box.install("FAKE_CURL_FAILS" => "1")

      assert_not status.success?
      assert_empty Dir.children(box.bin)
    end
  end

  test "the PATH hint shows when the folder is missing from PATH and not when it is there" do
    in_sandbox do |box|
      _, out = box.install
      assert_includes out, "export PATH=\"#{box.bin}:$PATH\""

      _, out = box.install("PATH" => "#{box.bin}:#{box.path}")
      assert_not_includes out, "export PATH"
    end
  end

  private

  Box = Struct.new(:dir, :site, :bin, :log, :path, keyword_init: true) do
    def env(extra = {})
      { "PATH" => path, "FAKE_LOG" => log, "CONTENTSPIEL_BIN_DIR" => bin,
        "CONTENTSPIEL_WRAPPER_URL" => "https://example.test/contentspiel" }.merge(extra)
    end

    def wrap(*args, chdir: site, **)
      Open3.capture2e(env, WRAPPER, *args, chdir: chdir).tap { |_, s| raise "wrapper failed" unless s.success? }
    end

    def wrap_raw(*args, chdir: site)
      Open3.capture2e(env, WRAPPER, *args, chdir: chdir)
    end

    def install(extra = {})
      out, status = Open3.capture2e(env(extra), "/bin/sh", INSTALLER)
      [ status, out ]
    end

    # Every fake call, as { args:, pwd: }, in order. The first line of an
    # entry is CALL (docker) or CURL; only docker calls are returned.
    def calls
      File.read(log).split(/^CALL\n/).drop(1).filter_map do |chunk|
        lines = chunk.lines.map(&:chomp)
        pwd = lines.pop.delete_prefix("PWD=")
        { args: lines, pwd: pwd } unless lines.first == "version"
      end
    end

    def run_call = calls.first
  end

  def in_sandbox
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)
      fakes = "#{dir}/fakes"
      FileUtils.mkdir_p [ fakes, "#{dir}/site", "#{dir}/bin" ]
      { "docker" => FAKE_DOCKER, "curl" => FAKE_CURL }.each do |name, body|
        File.write("#{fakes}/#{name}", body)
        File.chmod(0o755, "#{fakes}/#{name}")
      end
      File.write("#{dir}/log", "")
      yield Box.new(dir: dir, site: "#{dir}/site", bin: "#{dir}/bin", log: "#{dir}/log",
        path: "#{fakes}:/usr/bin:/bin:/usr/sbin:/sbin")
    end
  end
end
