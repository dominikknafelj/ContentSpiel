module ContentSpiel
  class Backup
    # Runs one tool (pg_dump, restic) for bin/backup and hands back what it
    # said. The child gets exactly the environment it is handed
    # (unsetenv_others: nothing of the accessory's own variables leaks into a
    # tool that does not need them), its stdin from /dev/null (an immediate
    # end of input on Linux and macOS alike: a tool that would prompt for a
    # password fails at once instead of waiting forever, and a closed fd 0 is
    # never left for the child's first open() to take), and is started
    # from its argv, never through a shell (a value is never parsed as a
    # command line). Its stdout and stderr are read to the end, in two threads
    # so a full pipe on one side never stalls the child; what they hold is the
    # caller's to classify, never to print. Plain Ruby, standard library only.
    #
    # A run's tools come with Backup::NICE in front (nice -n 19, ionice's idle
    # class), so a backup yields the CPU and the disk to the website. ionice
    # is util-linux's, Essential in Debian and named in the Dockerfile; on a
    # host where it is not in the child's PATH (a hand-built image, macOS) the
    # runner drops it from the argv and the tool runs under nice alone,
    # rather than a run failing for want of a priority (`without_ionice`).
    class Runner
      Outcome = Data.define(:exit_status, :stdout, :stderr)
      IONICE = %w[ionice -c 3 -t].freeze

      # argv without IONICE when it starts with nice and no folder of `path`
      # (the children's fixed PATH, Backup::PATH) holds an executable ionice.
      def self.without_ionice(argv, path)
        at = argv.each_cons(IONICE.size).find_index { |part| part == IONICE }
        return argv unless at && argv.first == "nice"
        return argv if path.to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "ionice")) }

        argv[0, at] + argv[(at + IONICE.size)..]
      end

      # The running child's pid, read by #interrupt: a plain variable and no
      # Mutex, because #interrupt is called from a signal trap, where a Mutex
      # cannot be taken.
      def initialize
        @pid = nil
      end

      def call(argv, env:)
        argv = self.class.without_ionice(argv, PATH)
        out_read, out_write = IO.pipe
        err_read, err_write = IO.pipe
        # in: File::NULL and not :close: whether a tool sees a closed stdin
        # depends on the tool's own runtime. GNU and BSD cat read the closed
        # fd 0 and fail with EBADF, while a Rust tool (uutils coreutils, the
        # default on ubuntu-26.04) reopens any closed fd 0-2 on /dev/null at
        # start and reads an empty input. A closed fd 0 is also free for the
        # child's first open() to take. /dev/null gives every tool the same
        # immediate EOF.
        pid = Process.spawn(env, [ argv.first, argv.first ], *argv.drop(1),
          unsetenv_others: true, in: File::NULL, out: out_write, err: err_write)
        @pid = pid
        [ out_write, err_write ].each(&:close)
        readers = [ out_read, err_read ].map { |io| Thread.new { io.read.force_encoding(Encoding::UTF_8) } }
        _, status = Process.wait2(pid)
        stdout, stderr = readers.map(&:value)
        Outcome.new(exit_status: status.exitstatus || 128 + status.termsig.to_i, stdout: stdout, stderr: stderr)
      ensure
        @pid = nil
        [ out_read, out_write, err_read, err_write ].each { |io| io&.close unless io&.closed? }
      end

      def running? = !@pid.nil?

      # TERM to the running child, if any: the schedule's stop ends a run
      # without waiting for a long upload.
      def interrupt
        pid = @pid
        Process.kill("TERM", pid) if pid
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
