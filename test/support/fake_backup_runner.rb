# A stand-in for ContentSpiel::Backup::Runner: records every call as
# [argv, env] and answers from a script keyed by the tool's step: "pg_dump",
# or restic's subcommand ("backup", "forget", "check", "snapshots", "init",
# "restore"). An answer is a Runner::Outcome, or a callable taking (argv, env)
# that returns one. A step the script leaves out succeeds with nothing said,
# but for "backup", whose default stdout is restic's --json summary line.
# A pg_dump that succeeds writes a file of `dump_bytes` at its --file, as the
# real one does.
class FakeBackupRunner
  Outcome = ContentSpiel::Backup::Runner::Outcome
  PREFIX = %w[nice -n 19 ionice -c 3 -t].freeze
  SNAPSHOT_ID = "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b".freeze

  attr_reader :calls, :interrupts

  def self.summary(processed, snapshot_id: SNAPSHOT_ID)
    %({"message_type":"summary","snapshot_id":"#{snapshot_id}","total_bytes_processed":#{processed}})
  end

  # The script is a Hash, or its steps given as `"step" => answer` arguments.
  def initialize(script = {}, dump_bytes: 1_234, processed_bytes: 101_234, **steps)
    @script = script.merge(steps)
    @dump_bytes = dump_bytes
    @processed_bytes = processed_bytes
    @calls = []
    @interrupts = 0
  end

  def call(argv, env:)
    @calls << [ argv, env ]
    step = self.class.step(argv)
    answer = @script.fetch(step) { default(step) }
    answer = answer.call(argv, env) if answer.respond_to?(:call)
    write_dump(argv) if step == "pg_dump" && answer.exit_status.zero?
    answer
  end

  def interrupt = @interrupts += 1

  # The tool's argv without the nice/ionice prefix.
  def self.bare(argv) = argv.first(PREFIX.size) == PREFIX ? argv.drop(PREFIX.size) : argv

  def self.step(argv)
    tool, subcommand = bare(argv)
    tool == "restic" ? subcommand : tool
  end

  def steps = calls.map { |argv, _| self.class.step(argv) }

  def call_for(step) = calls.find { |argv, _| self.class.step(argv) == step }

  private

  def default(step)
    stdout = step == "backup" ? "#{self.class.summary(@processed_bytes)}\n" : ""
    Outcome.new(exit_status: 0, stdout: stdout, stderr: "")
  end

  def write_dump(argv)
    file = argv[argv.index("--file") + 1]
    File.binwrite(file, "x" * @dump_bytes)
  end
end
