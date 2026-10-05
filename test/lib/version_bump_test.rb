require "test_helper"
require "ripper"

# The public content version (`app/models/public_site.rb`, technical cleanup
# spec §4.8 and §10) is moved from the models' `after_commit` -- and a write
# that goes around the callbacks moves nothing by itself. Such a write to a
# table a public page is built from, with no bump beside it, serves the old
# page (and a 304 for it) until something else bumps.
#
# So under `app/` and `lib/`, every line of code that writes around the
# callbacks --
#
#   update_all  update_columns  update_column  touch_all  insert_all(!)
#   upsert_all  delete_all (also as `dependent: :delete_all`)  delete_by
#   insert(!)  upsert  record.delete  Model.delete(id)
#   update_counters  increment_counter  decrement_counter  increment!
#   decrement!
#   connection.execute / exec_... / update / delete / insert, and
#   `.execute(` / `.exec_...(` on any receiver (a `with_connection` block's
#   variable)
#
# -- must be one of:
#
#   1. in a file whose code calls `PublicSite.bump_version!` (whoever wrote
#      the bulk write there has decided when it bumps);
#   2. marked on the line itself: `# version: none (the reason)`;
#   3. a write whose receiver is a model no public page reads (RECEIVERS), or
#      in a file that writes only such a table (FILES) -- each with its reason.
#
# Any receiver counts, not only the eight version-relevant models by name:
# most of these writes are on a variable (`page.update_columns`,
# `blocks[id].update_columns`, `model.where(...).update_all`), where no
# constant says which table it is.
#
# `destroy_all` is not in the list: it runs the callbacks. Neither is
# `touch`, which runs `after_commit`.
#
# The lists can't rot: a `# version: none` on a line with no such write, and
# a RECEIVERS or FILES entry that excuses nothing, both fail.
#
# A tripwire, not a proof, like `service_contract_test.rb`: a file passes by
# bumping anywhere in it. Whether each path bumps when it should is
# `test/models/public_site/version_test.rb`.
class VersionBumpTest < ActiveSupport::TestCase
  ROOTS = %w[app lib].freeze
  EXTENSIONS = %w[rb rake].freeze

  WRITE = /
    \b(?:update_all|update_columns|update_column|touch_all|insert_all!?|upsert_all|delete_all|delete_by|
       update_counters|increment_counter|decrement_counter)(?![\w?])
    |
    \b(?:insert|upsert)!?\(              # one row, around the callbacks -- and Array#insert, which gets a mark
    |
    \.(?:increment|decrement)!
    |
    \b[A-Z][\w:]*\.delete\(             # Model.delete(id)
    |
    \.delete(?![\w(?!])                 # record.delete: no argument, where Hash, Array and String#delete take one
    |
    \.(?:execute|exec_\w+)\(            # raw SQL, on `connection` or on a block's variable
    |
    \bconnection\.(?:execute|exec_\w+|update|delete|insert)\b
  /x

  BUMP = /\bPublicSite\.bump_version!/
  # The whole trailing comment starts with it, so prose that mentions the
  # mark is not one.
  MARK = /\A#\s*version:\s*none\b\s*(?:\((?<reason>[^)]*)\))?/

  # Models no public page reads. A write counts as theirs when the constant
  # starts the line's statement (`User.where(...).touch_all`), not when it
  # merely appears in an argument.
  RECEIVERS = {
    "User" => "accounts; the public site shows no user, not even a post's author",
    "ApiToken" => "API tokens",
    "AccessControl::Group" => "groups and their stale-check base",
    "Media::Usage" => "media_usages is derived from the pages, blocks and posts whose own writes bump; no page reads it"
  }.freeze

  # Files that write only tables no public page reads, where the receiver is
  # a scope held in a variable or continued from the line above.
  FILES = {
    "app/models/public_site/version.rb" => "the counter's own row: this write is the bump",
    "app/models/translations/state_index.rb" => "writes only translation_states (`State`), which CS Studio's lists read and no public page does"
  }.freeze

  Write = Struct.new(:path, :line, :code, :comment)

  # Every guarded write in `source`, with the comment that shares its line.
  def self.writes(path, source)
    code, comments = split(source)
    code.each_line.with_index(1).filter_map do |text, number|
      Write.new(path, number, text.strip, comments[number].to_s) if text.match?(WRITE)
    end
  end

  # The source with every comment and every string's text blanked (line
  # breaks kept, so a line number still names the line), and the comments by
  # line. Ripper does the lexing, so a `#` inside a string or an
  # interpolation is not a comment, and a method named in a message or in a
  # piece of SQL is not a call -- the call that runs the SQL is.
  BLANKED = %i[on_comment on_embdoc_beg on_embdoc on_embdoc_end on_tstring_content].freeze

  def self.split(source)
    comments = {}
    code = Ripper.lex(source).map do |(line, _column), type, token, _state|
      next token unless BLANKED.include?(type)

      comments[line] = token if type == :on_comment
      token.gsub(/[^\n]/, " ")
    end.join
    [ code, comments ]
  end

  # Why `write` is let through, or nil when it isn't.
  def self.excuse(write, source_code)
    return :bumps if source_code.match?(BUMP)
    return :marked if write.comment.match(MARK)&.[](:reason).to_s.strip.present?
    return [ :file, write.path ] if FILES.key?(write.path)

    receiver = RECEIVERS.keys.find { |name| write.code.match?(/\A#{Regexp.escape(name)}\.[^;]*(?:#{WRITE.source})/x) }
    [ :receiver, receiver ] if receiver
  end

  def self.sources
    ROOTS.flat_map { |root| EXTENSIONS.flat_map { |extension| Rails.root.glob("#{root}/**/*.#{extension}") } }.sort
      .to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }
  end

  # `[offences, excuses used]` for `sources` (`{ relative path => source }`).
  def self.check(sources)
    offences = []
    used = []
    sources.each do |path, source|
      code, comments = split(source)
      found = writes(path, source)
      found.each do |write|
        excuse = excuse(write, code)
        excuse ? used << excuse : offences << "#{path}:#{write.line}: #{write.code}"
      end

      lines = found.map(&:line)
      comments.each do |line, comment|
        mark = comment.match(MARK) or next
        offences << "#{path}:#{line}: `# version: none` needs its reason in brackets" if mark[:reason].to_s.strip.empty?
        offences << "#{path}:#{line}: `# version: none` on a line with no write around the callbacks" unless lines.include?(line)
      end
    end
    [ offences, used ]
  end

  test "every write around the callbacks bumps the public content version or says why it needn't" do
    offences, = self.class.check(self.class.sources)

    assert_empty offences, <<~MESSAGE
      These lines write around the model callbacks, so no `after_commit` moves the public
      content version for them. If the write can change a public page, call
      `PublicSite.bump_version!` beside it (it waits for the commit). If it can't, end the
      line with `# version: none (why not)`.

      #{offences.join("\n")}
    MESSAGE
  end

  test "every allow-list entry still excuses something" do
    _, used = self.class.check(self.class.sources)

    RECEIVERS.each_key { |name| assert_includes used, [ :receiver, name ], "RECEIVERS[#{name.inspect}] excuses no write any more: remove it" }
    FILES.each_key { |path| assert_includes used, [ :file, path ], "FILES[#{path.inspect}] excuses no write any more: remove it" }
  end

  # --- The guard itself --------------------------------------------------------

  def offences_in(source) = self.class.check("app/services/example.rb" => source).first

  test "a bulk write on a variable, with no bump in the file, is an offence" do
    assert_equal [ "app/services/example.rb:2: page.update_columns(position: 1)" ], offences_in(<<~RUBY)
      def call
        page.update_columns(position: 1)
      end
    RUBY
  end

  test "each guarded method is caught, also as a dependent option and as raw SQL" do
    %w[update_all update_columns update_column touch_all insert_all insert_all! upsert_all delete_all update_counters].each do |name|
      assert_equal 1, offences_in("Page.where(id: 1).#{name}(x)\n").size, name
    end
    assert_equal 1, offences_in("has_many :public_paths, dependent: :delete_all\n").size
    assert_equal 1, offences_in(%(Page.connection.execute("UPDATE pages SET position = 0")\n)).size
  end

  test "single-row writes around the callbacks are caught" do
    [
      "PublicPath.delete_by(locale: code)",
      "PublicPath.insert({ path: path })",
      "PublicPath.insert!({ path: path })",
      "PublicPath.upsert({ path: path }, unique_by: :id)",
      "upsert({ id: 1 })",
      "page.delete",
      "page&.delete",
      "Page.delete(id)",
      "Media::Asset.delete(ids)",
      "page.increment!(:position)",
      "page.decrement!(:position)",
      "Page.update_counters(id, position: 1)"
    ].each { |line| assert_equal 1, offences_in("#{line}\n").size, line }
  end

  test "raw SQL is caught on the connection and on a block's variable" do
    [
      %(Page.connection.update("UPDATE pages SET position = 0")),
      %(Page.connection.delete("DELETE FROM public_paths")),
      %(Page.connection.insert("INSERT INTO public_paths DEFAULT VALUES")),
      %(Page.connection.exec_update("UPDATE pages SET position = 0")),
      %(Page.with_connection { |c| c.execute("UPDATE pages SET position = 0") }),
      %(Page.with_connection { |c| c.exec_delete("DELETE FROM public_paths") })
    ].each { |line| assert_equal 1, offences_in("#{line}\n").size, line }
  end

  test "a delete that takes an argument on a variable is a Hash, Array or String's, not a write" do
    assert_empty offences_in(<<~RUBY)
      settings.delete("tag")
      names.delete(name)
      value.delete!("-")
      link_to "Remove", path, data: { turbo_method: :delete }
    RUBY
  end

  test "a bump anywhere in the file's code lets its writes through; one in a comment does not" do
    assert_empty offences_in("Page.where(id: ids).update_all(x: 1)\nPublicSite.bump_version!\n")
    assert_equal 1, offences_in("Page.where(id: ids).update_all(x: 1)\n# PublicSite.bump_version! is not needed\n").size
  end

  test "a mark with a reason lets its own line through, and only that line" do
    assert_empty offences_in("record.update_columns(a: 1) # version: none (bookkeeping no page renders)\n")
    assert_equal [ "app/services/example.rb:2: other.update_columns(b: 2)" ],
      offences_in("record.update_columns(a: 1) # version: none (bookkeeping)\nother.update_columns(b: 2)\n")
  end

  test "a mark without a reason, or on a line with no such write, is an offence" do
    assert_equal 2, offences_in("record.update_columns(a: 1) # version: none\n").size
    assert_equal 1, offences_in("record.update_columns(a: 1) # version: none ( )\n").grep(/needs its reason/).size
    assert_equal [ "app/services/example.rb:1: `# version: none` on a line with no write around the callbacks" ],
      offences_in("record.save! # version: none (left over)\n")
  end

  test "a write to a table no public page reads is let through by its receiver, and no other is" do
    assert_empty offences_in("User.where(id: ids).touch_all\nAccessControl::Group.where(id: ids).touch_all\n")
    assert_equal 1, offences_in("Post.where(author_id: User.first.id).update_all(author_id: nil)\n").size
    assert_equal 1, offences_in("SuperUser.where(id: ids).touch_all\n").size
  end

  test "a method that only resembles one, and a name in a string or a comment, are not writes" do
    assert_empty offences_in(<<~RUBY)
      # update_all would skip the callbacks here
      records.each(&:delete_all_marks)
      message = "run update_all by hand"
    RUBY
  end
end
