module ContentSpiel
  # THE SETTINGS ROW IS A TRANSACTION'S FIRST LOCK, checked in development
  # and test. Its writers (`Settings::Save`, `Locales::*`,
  # `StarterContents::Add`, the setup wizard's last step) take it
  # `FOR UPDATE` as their first statement and then write pages, posts, blocks
  # and the rows derived from them; `Locales::Enable` writes every page and
  # post row. A transaction that writes or locks one of those rows and only
  # then asks for the settings row (`ContentTypes.hold!`, `FOR SHARE`) waits
  # for such a writer while it holds what the writer will wait for: Postgres
  # ends one of the two with `ActiveRecord::Deadlocked`
  # (`test/services/locales/enable_race_test.rb`). So the order is the
  # settings row, then the page's or post's row, then the block rows, then
  # what is derived from them.
  #
  # A transaction that holds the row `FOR SHARE` and then UPDATEs it or locks
  # it `FOR UPDATE` upgrades its lock: two such transactions each hold the
  # share the other's upgrade waits for, and deadlock
  # (`test/controllers/setup_review_race_test.rb`). A transaction that will
  # write the row takes it `FOR UPDATE` first (`site.lock!`); a share taken
  # after that is free.
  #
  # Every SQL statement is heard (`config/initializers/lock_order.rb`), and a
  # stack of the connection's transaction and savepoints is kept from the
  # statements that open and close them: a frame remembers the first statement
  # that wrote or locked one of `AFTER`'s rows, and how strongly the settings
  # row is held (`:share` or `:update`). A statement that takes the settings
  # row after a frame of the open transaction wrote or locked such a row,
  # with the settings row not held yet, raises `Violation`; so does one that
  # takes it for an update while the transaction holds it only `FOR SHARE`.
  # Taking it again at the same strength or weaker is free, so a `hold!` deep
  # in `PublicSite::Paths.refresh` or `SiteSearch::Indexing` is checked to be
  # either the transaction's first lock or one already held.
  #
  # Comments are taken out of a statement before it is read: development's
  # query log tags append one to every statement, `COMMIT` and `ROLLBACK`
  # included (`config/environments/development.rb`), and a tag prepended
  # would hide even `BEGIN`. A transaction ends at `COMMIT`, `END`,
  # `ROLLBACK`, `ABORT` or `PREPARE TRANSACTION`; `AND CHAIN` begins the next
  # one at once (Rails' `restart_db_transaction` sends `ROLLBACK AND CHAIN`).
  # A savepoint rolled back takes its frame's write and hold with it, as
  # Postgres releases the locks taken under it; one released gives them to
  # its parent. What runs outside a transaction is its own statement and is
  # not followed. A transactional test's own transaction is forgotten when
  # the test starts (`test/test_helper.rb`), so a test's setup rows are not
  # the write's and the first savepoint the code opens stands where its real
  # transaction would. `KEY SHARE` (a foreign key's check) is not a lock here:
  # it does not wait for a writer's UPDATE of a row.
  #
  # Read from the SQL a statement sends through Active Record, so a lock
  # taken some other way (an advisory lock, a raw `LOCK TABLE`, SQL sent
  # outside Active Record) is not seen, nor a path no test or development
  # request runs; production does not check. In `lib/` and not reloaded,
  # because `STACKS`, each connection's open transaction, must outlive a code
  # reload in development.
  module LockOrder
    class Violation < RuntimeError; end

    # What the settings row's writers write after taking it.
    AFTER = %w[pages posts content_blocks public_paths published_versions translation_states search_entries].freeze
    TABLE = "\"(?:#{AFTER.join("|")})\"".freeze
    ROW_LOCK = '\bFOR\s+(?:NO\s+KEY\s+)?(?:UPDATE|SHARE)\b'
    TOUCH = /\b(?:UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+#{TABLE}|\bFROM\s+#{TABLE}.*#{ROW_LOCK}/m
    SETTINGS_UPDATE = /\A(?:UPDATE|DELETE\s+FROM)\s+"site_settings"|\bFROM\s+"site_settings".*\bFOR\s+(?:NO\s+KEY\s+)?UPDATE\b/m
    SETTINGS_SHARE = /\bFROM\s+"site_settings".*\bFOR\s+SHARE\b/m
    STRENGTH = { share: 1, update: 2 }.freeze

    # A quoted literal or name is kept as it is (a "--" inside one is no
    # comment); a comment is replaced by a space.
    LITERAL_OR_COMMENT = %r{'(?:[^']|'')*'|"(?:[^"]|"")*"|/\*.*?\*/|--[^\n]*}m

    BEGINS = /\A(?:BEGIN|START\s+TRANSACTION)\b/i
    ENDS = /\A(?:COMMIT|END|ROLLBACK|ABORT)(?:\s+(?:WORK|TRANSACTION))?(?:\s+AND\s+(NO\s+)?(CHAIN))?\z|\APREPARE\s+TRANSACTION\b/i
    SAVEPOINT = /\ASAVEPOINT\s+("?)([^\s"]+)\1\z/i
    RELEASE = /\ARELEASE\s+(?:SAVEPOINT\s+)?("?)([^\s"]+)\1\z/i
    ROLL_BACK_TO = /\AROLLBACK\s+(?:(?:WORK|TRANSACTION)\s+)?TO\s+(?:SAVEPOINT\s+)?("?)([^\s"]+)\1\z/i

    # `held` is the strength the frame holds the settings row at, `shared`
    # the statement that took it `FOR SHARE` (for the upgrade's message).
    Frame = Struct.new(:savepoint, :touch, :held, :shared)

    STACKS = ObjectSpace::WeakKeyMap.new
    STACKS_LOCK = Mutex.new

    module_function

    # One statement, as `sql.active_record` hands it over.
    def heard(payload)
      connection = payload[:connection]
      return if connection.nil? || payload[:cached] || payload[:name] == "SCHEMA"

      sql = bare(payload[:sql].to_s)
      frames = STACKS_LOCK.synchronize { STACKS[connection] ||= [] }
      case sql
      when BEGINS then frames.replace([ Frame.new ])
      when ENDS then frames.replace($2 && !$1 ? [ Frame.new ] : [])
      when SAVEPOINT then open_savepoint(frames, $2)
      when RELEASE then release(frames, $2)
      when ROLL_BACK_TO then roll_back_to(frames, $2)
      else statement(frames, sql) if frames.any?
      end
    end

    # The statement without its comments, its surrounding space or a
    # closing semicolon.
    def bare(sql)
      sql.gsub(LITERAL_OR_COMMENT) { |part| part.start_with?("/*", "--") ? " " : part }.strip.delete_suffix(";").rstrip
    end

    # The connection's open transaction is not followed any further: its
    # statements so far are no write's (a transactional test's own).
    def forget(connection) = STACKS_LOCK.synchronize { STACKS[connection] = [] }

    # The block's statements are followed as another transaction's: a test
    # that stands in for another process's write inside a running one (a
    # write while a build sends its batch) runs it on the same connection.
    def aside(connection)
      outer = STACKS_LOCK.synchronize { STACKS[connection].tap { STACKS[connection] = [] } }
      yield
    ensure
      STACKS_LOCK.synchronize { STACKS[connection] = outer || [] }
    end

    def statement(frames, sql)
      held = strongest(frames.map(&:held))
      if (taken = settings_strength(sql))
        if held.nil?
          touch = frames.filter_map(&:touch).first
          raise Violation, violation(touch, sql) if touch
        elsif held == :share && taken == :update
          raise Violation, upgrade(frames.filter_map(&:shared).first, sql)
        end

        frame = frames.last
        frame.shared ||= sql if taken == :share
        frame.held = strongest([ frame.held, taken ])
      elsif !held && sql.match?(TOUCH)
        frames.last.touch ||= sql
      end
    end

    def settings_strength(sql)
      if sql.match?(SETTINGS_UPDATE) then :update
      elsif sql.match?(SETTINGS_SHARE) then :share
      end
    end

    def strongest(strengths) = strengths.compact.max_by { |strength| STRENGTH.fetch(strength) }

    # A savepoint of a name already open releases that one first: Active
    # Record names a savepoint by its depth and, after rolling one back, goes
    # on in its parent without releasing it, so what that frame heard since
    # was the parent's.
    def open_savepoint(frames, name)
      release(frames, name)
      frames << Frame.new(name)
    end

    def release(frames, name)
      index = frames.rindex { |frame| frame.savepoint == name } or return
      released = frames.slice!(index..)
      parent = frames.last or return
      parent.touch ||= released.filter_map(&:touch).first
      parent.held = strongest([ parent.held, *released.map(&:held) ])
      parent.shared ||= released.filter_map(&:shared).first
    end

    def roll_back_to(frames, name)
      index = frames.rindex { |frame| frame.savepoint == name } or return
      frames.slice!((index + 1)..)
      frames[index].touch = nil
      frames[index].held = nil
      frames[index].shared = nil
    end

    def violation(touch, sql)
      "the settings row is taken after a row it comes before, in one transaction:\n" \
        "  first: #{touch.squish.truncate(300)}\n  then:  #{sql.squish.truncate(300)}\n" \
        "Take it first: `ContentTypes.hold!` as the transaction's first statement (`ContentSpiel::LockOrder`)."
    end

    def upgrade(shared, sql)
      "the settings row is held FOR SHARE and then taken for an update, in one transaction (two such transactions deadlock):\n" \
        "  first: #{shared.to_s.squish.truncate(300)}\n  then:  #{sql.squish.truncate(300)}\n" \
        "Take it FOR UPDATE first: `site.lock!` as the transaction's first statement (`ContentSpiel::LockOrder`)."
    end

    private_class_method :statement, :settings_strength, :strongest, :open_savepoint, :release, :roll_back_to, :violation, :upgrade
  end
end
