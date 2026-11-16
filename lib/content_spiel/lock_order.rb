module ContentSpiel
  # THE SETTINGS ROW IS A TRANSACTION'S FIRST LOCK, checked in development
  # and test. Its writers (`Settings::Save`, `Locales::*`,
  # `StarterContents::Add`) take it `FOR UPDATE` as their first statement and
  # then write pages, posts, blocks and the rows derived from them;
  # `Locales::Enable` writes every page and post row. A transaction that
  # writes or locks one of those rows and only then asks for the settings row
  # (`ContentTypes.hold!`, `FOR SHARE`) waits for such a writer while it holds
  # what the writer will wait for: Postgres ends one of the two with
  # `ActiveRecord::Deadlocked` (`test/services/locales/enable_race_test.rb`).
  # So the order is the settings row, then the page's or post's row, then the
  # block rows, then what is derived from them.
  #
  # Every SQL statement is heard (`config/initializers/lock_order.rb`), and a
  # stack of the connection's transaction and savepoints is kept from the
  # statements that open and close them: a frame remembers the first statement
  # that wrote or locked one of `AFTER`'s rows, and whether the settings row
  # is held. A statement that takes the settings row (a lock of it or an
  # UPDATE) after a frame of the open transaction wrote or locked such a row,
  # with the settings row not held yet, raises `Violation`. Taking it again
  # once held is free and is never a violation, so a `hold!` deep in
  # `PublicSite::Paths.refresh` or `SiteSearch::Indexing` is checked to be
  # either the transaction's first lock or one already held.
  #
  # A savepoint rolled back takes its frame's write and hold with it, as
  # Postgres releases the locks taken under it; one released gives them to
  # its parent. What runs outside a
  # transaction is its own statement and is not followed. A transactional
  # test's own transaction is forgotten when the test starts
  # (`test/test_helper.rb`), so a test's setup rows are not the write's and
  # the first savepoint the code opens stands where its real transaction
  # would. `KEY SHARE` (a foreign key's check) is not a lock here: it does
  # not wait for a writer's UPDATE of a row.
  #
  # Read from the SQL a statement sends, so a lock taken some other way (an
  # advisory lock, a raw `LOCK TABLE`) is not seen.
  module LockOrder
    class Violation < RuntimeError; end

    # What the settings row's writers write after taking it.
    AFTER = %w[pages posts content_blocks public_paths published_versions translation_states search_entries].freeze
    TABLE = "\"(?:#{AFTER.join("|")})\"".freeze
    ROW_LOCK = '\bFOR\s+(?:NO\s+KEY\s+)?(?:UPDATE|SHARE)\b'
    TOUCH = /\b(?:UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+#{TABLE}|\bFROM\s+#{TABLE}.*#{ROW_LOCK}/m
    SETTINGS = /\A\s*UPDATE\s+"site_settings"|\bFROM\s+"site_settings".*#{ROW_LOCK}/m

    Frame = Struct.new(:savepoint, :touch, :held)

    STACKS = ObjectSpace::WeakKeyMap.new
    STACKS_LOCK = Mutex.new

    module_function

    # One statement, as `sql.active_record` hands it over.
    def heard(payload)
      connection = payload[:connection]
      return if connection.nil? || payload[:cached] || payload[:name] == "SCHEMA"

      sql = payload[:sql].to_s
      frames = STACKS_LOCK.synchronize { STACKS[connection] ||= [] }
      case sql
      when /\A\s*BEGIN\b/i then frames.replace([ Frame.new ])
      when /\A\s*(?:COMMIT|ROLLBACK)\s*\z/i then frames.clear
      when /\A\s*SAVEPOINT\s+(\S+)/i then open_savepoint(frames, $1)
      when /\A\s*RELEASE\s+SAVEPOINT\s+(\S+)/i then release(frames, $1)
      when /\A\s*ROLLBACK\s+TO\s+SAVEPOINT\s+(\S+)/i then roll_back_to(frames, $1)
      else statement(frames, sql) if frames.any?
      end
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
      held = frames.any?(&:held)
      if sql.match?(SETTINGS)
        touch = frames.filter_map(&:touch).first
        raise Violation, violation(touch, sql) if touch && !held

        frames.last.held = true
      elsif !held && sql.match?(TOUCH)
        frames.last.touch ||= sql
      end
    end

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
      parent.held ||= released.any?(&:held)
    end

    def roll_back_to(frames, name)
      index = frames.rindex { |frame| frame.savepoint == name } or return
      frames.slice!((index + 1)..)
      frames[index].touch = nil
      frames[index].held = nil
    end

    def violation(touch, sql)
      "the settings row is taken after a row it comes before, in one transaction:\n" \
        "  first: #{touch.squish.truncate(300)}\n  then:  #{sql.squish.truncate(300)}\n" \
        "Take it first: `ContentTypes.hold!` as the transaction's first statement (`ContentSpiel::LockOrder`)."
    end

    private_class_method :statement, :open_savepoint, :release, :roll_back_to, :violation
  end
end
