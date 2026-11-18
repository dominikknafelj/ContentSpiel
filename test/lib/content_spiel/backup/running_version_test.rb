require "test_helper"
require "tmpdir"

class ContentSpiel::Backup::RunningVersionTest < ActiveSupport::TestCase
  RunningVersion = ContentSpiel::Backup::RunningVersion

  setup do
    @root = Pathname(Dir.mktmpdir)
    @path = RunningVersion.path(@root)
  end

  teardown { FileUtils.remove_entry(@root) }

  test "the file is beside the status file, read back whole, its time in UTC" do
    assert_equal @root.join("storage", "backup", "accessory.json"), @path
    written = RunningVersion.new(cms_version: "0.11.0", started_at: Time.utc(2026, 11, 18, 2, 59, 30))
    written.write(@path)

    assert_equal written, RunningVersion.read(@path)
    assert_equal({ "cms_version" => "0.11.0", "started_at" => "2026-11-18T02:59:30Z" }, JSON.parse(@path.read))
    assert_predicate RunningVersion.read(@path).started_at, :utc?
    assert_equal 0o644, @path.stat.mode & 0o777
  end

  test "no file, or one that is not this JSON, reads as nil" do
    assert_nil RunningVersion.read(@path)

    @path.dirname.mkpath
    [ "", "{", "[]", "null", "{}", %({"cms_version": 11, "started_at": "2026-11-18T02:59:30Z"}),
      %({"cms_version": "", "started_at": "2026-11-18T02:59:30Z"}),
      %({"cms_version": "0.11.0", "started_at": "yesterday"}), "\xFF\xFE" ].each do |text|
      @path.binwrite(text)
      assert_nil RunningVersion.read(@path), text.inspect
    end

    @path.write(%({"cms_version": "0.11.0"}))
    assert_equal RunningVersion.new(cms_version: "0.11.0", started_at: nil), RunningVersion.read(@path)
  end
end
