require "pathname"
require "json"
require "fileutils"

module ContentSpiel
  # `contentspiel generate KIND NAME ["Label"]` (bin/contentspiel): adds one
  # choice to a site's theme the way `rails generate` adds a file, so that the
  # theme passes `Theme::Check` afterwards (releases spec, "Generators").
  #
  #   ContentSpiel::ThemeGenerators.new("/site/theme").generate("section_style", "banner", "Banner")
  #   # => ["theme.yml", "assets/stylesheets/theme.css"], the paths written, under the theme
  #
  # Each kind is an entry in one list of `theme.yml` and the file that draws
  # it (theme-choices reference):
  # - a section style: an entry of `section_styles`, and its class
  #   `.content-section--style-<name>` appended to the theme's one
  #   stylesheet, the class the default Section template writes. A theme
  #   holds no other stylesheet (`Theme::Check#misplaced`), so it is a rule
  #   in that file and never a file of its own;
  # - a page template: an entry of `page_templates`, and
  #   `views/pages/templates/_<name>.html.erb`, a copy of the theme's own
  #   Standard template (the CMS's when the theme does not hold one), so the
  #   new template draws a page from the first reload.
  #
  # THE RULES ARE THE DECLARATIONS' OWN. A name is judged by
  # `Theme::Declarations::NAME`, a taken one by `Theme::Declarations.of`
  # (the lists as the site sees them, the inherited ones included), and the
  # file as it will be written is read again by `Theme::Declarations.read`
  # before anything is written: whatever that reader refuses, this refuses,
  # and no second rule is kept here to drift from it.
  #
  # A LIST THE THEME DOES NOT DECLARE IS THE DEFAULT'S, and a list it declares
  # replaces the default's whole. So the first page template of a theme that
  # inherits `page_templates` is written into a new list that begins with the
  # default's own entries (standard, landing): without them every page left
  # on those templates would lose its template, and the theme's copies of
  # their files would be named by no entry, which the check refuses. The
  # default declares no section styles, so that list starts with the new one.
  #
  # THEME.YML IS EDITED AS TEXT, never dumped again: it is the author's file,
  # with the scaffold's comments in it, and a dump would drop every comment
  # and reorder what was written. The new entry goes after the last entry of
  # its list (where the parser says that list ends), a list that is absent
  # is added at the end of the file, and `[]` is replaced by the entry. A
  # list written in flow style with entries (`[{name: a, label: A}]`) is
  # refused with the lines to add by hand.
  #
  # NOTHING IS WRITTEN UNLESS EVERYTHING CAN BE: every refusal is raised
  # before the first write, and the stub is written before `theme.yml`, so a
  # failure between the two leaves a file the check names, never an entry
  # that draws nothing.
  #
  # Needs the application (the declarations, the contract and the default
  # theme's files are application code): bin/contentspiel starts it first.
  # Not autoloaded, for the reason site_generator.rb gives (config/application.rb).
  class ThemeGenerators
    class Refused < StandardError; end

    # What can be generated: the kind as typed => the list of theme.yml.
    KINDS = { "section_style" => "section_styles", "page_template" => "page_templates" }.freeze

    STYLESHEET = "assets/stylesheets/theme.css".freeze

    USAGE = "contentspiel generate section_style NAME \"Label\", or contentspiel generate page_template NAME \"Label\"".freeze

    attr_reader :theme

    def initialize(theme)
      @theme = Pathname(File.expand_path(theme.to_s))
    end

    # The paths written, relative to the theme, theme.yml first. Raises Refused.
    def generate(kind, name, label = nil)
      list = KINDS[kind.to_s] or raise Refused, "contentspiel generate makes one of: #{KINDS.keys.join(", ")}, not #{kind.to_s.inspect}. #{USAGE}"
      name = name.to_s
      label = label.nil? ? default_label(name) : label.to_s.strip
      raise Refused, name_refusal(name) unless name.match?(Theme::Declarations::NAME)
      raise Refused, "The label of #{name} is empty. Give the words a person sees in CS Studio: #{USAGE}" if label.empty?

      folder = ThemeFolder.new(theme)
      source = declarations_source
      problems = Theme::Declarations.read(source, folder: folder).last
      if problems.any?
        raise Refused, "#{Theme::Declarations::FILE} has problems, so nothing is added to it: #{problems.join(" ")} " \
                       "Fix them first (contentspiel check lists them all)."
      end
      current = Theme::Declarations.of(folder).fetch(list)
      if current.any? { |choice| choice.name == name }
        raise Refused, "#{list} already has an entry named #{name}#{own?(source, list) ? "" : " (the default theme's, which this theme inherits)"}. " \
                       "Choose another name."
      end

      edited = add_entry(source, list, name, label, current)
      stub, content = stub_for(kind, name)
      raise Refused, "#{stub} already exists. Move it away, or choose another name." if kind == "page_template" && theme.join(stub).exist?

      write(stub, content, append: kind == "section_style")
      write(Theme::Declarations::FILE, edited)
      [ Theme::Declarations::FILE, stub ]
    end

    private

    def name_refusal(name)
      "#{name.empty? ? "An empty name" : name.inspect} is not a name a theme may declare: a name is lowercase letters, " \
        "digits and underscores, a letter first, at most 40 (#{Theme::Declarations::FILE}'s own rule). For example: #{USAGE}"
    end

    # banner => Banner, two_columns => Two columns.
    def default_label(name) = name.tr("_", " ").capitalize

    def declarations_source
      file = theme.join(Theme::Declarations::FILE)
      file.file? ? file.read : ""
    end

    # The list's key node and its value in the parsed file, or nil.
    def list_node(source, list)
      # A file of comments alone is no document: `parse` answers false.
      document = Psych.parse(source)
      mapping = document.is_a?(Psych::Nodes::Document) ? document.root : nil
      return nil unless mapping.is_a?(Psych::Nodes::Mapping)

      mapping.children.each_slice(2).find { |key, _| key.is_a?(Psych::Nodes::Scalar) && key.value == list }
    end

    def own?(source, list) = !list_node(source, list).nil?

    # The file with the entry added, read back by the declarations' reader
    # and compared: the list must be what it was plus the new entry, and the
    # file must have no problem. Otherwise the edit is not trusted.
    def add_entry(source, list, name, label, current)
      key, value = list_node(source, list)
      entry = ->(indent) { entry_lines(name, label).map { |line| "#{indent}#{line}" } }
      edited =
        if key.nil?
          inherited = list == "page_templates" ? current.flat_map { |choice| Theme::Scaffold.entry_lines(list, choice) } : []
          body = [ "#{list}:", *inherited, *entry.("  ") ].join("\n")
          [ source.empty? || source.end_with?("\n") ? source : "#{source}\n", source.strip.empty? ? "" : "\n", body, "\n" ].join
        elsif value.is_a?(Psych::Nodes::Sequence) && value.children.empty?
          replace_empty(source, key, value, entry.("  "))
        elsif value.is_a?(Psych::Nodes::Sequence) && value.style == Psych::Nodes::Sequence::BLOCK
          insert_after(source, value, entry.(" " * value.start_column))
        end

      # Every entry that was there, as it was (name, labels, fields: an
      # insertion inside a block scalar would change a label), then the new one.
      shape = ->(choices) { choices.map { |choice| [ choice.name, choice.labels, choice.fields ] } }
      expected = shape.(current) + [ [ name, { "en" => label }, [] ] ]
      lists, problems = edited ? Theme::Declarations.read(edited, folder: ThemeFolder.new(theme)) : [ {}, [ "not edited" ] ]
      return edited if problems.empty? && shape.(lists.fetch(list, [])) == expected

      raise Refused, "#{Theme::Declarations::FILE} writes #{list} in a form this command does not add to. Add these lines " \
                     "to the list by hand, as an entry of its own:\n#{entry.("  ").join("\n")}"
    end

    # `list: []` becomes `list:` with the entry below it.
    def replace_empty(source, key, value, lines)
      return nil unless key.start_line == value.end_line

      rows = source.lines
      row = rows[key.start_line]
      rest = row[value.end_column..].to_s
      return nil unless rest.strip.empty? || rest.strip.start_with?("#")

      rows[key.start_line] = "#{row[0...value.start_column].rstrip}\n#{lines.join("\n")}\n"
      rows.join
    end

    # The entry on the line after the list's last entry ends.
    #
    # Psych ends a block mapping where the NEXT token starts, past every
    # blank and comment line after it, so `end_line` of the last entry can
    # be the line of the next key, with that key's own heading comment
    # (`# Page templates below`) above it. The insertion steps back over
    # those lines to just after the entry's last line of content, so a
    # comment stays with the key it stands above. A comment line indented
    # deeper than the entry's keys may be content of a block scalar (a
    # `label: |`) and is not stepped over; the read-back in `add_entry`
    # refuses whatever an insertion would still change.
    def insert_after(source, sequence, lines)
      last = sequence.children.last
      rows = source.lines
      rows[-1] = "#{rows[-1]}\n" if rows.any? && !rows[-1].end_with?("\n")
      at = last.end_column.zero? ? last.end_line : last.end_line + 1
      if last.end_column.zero?
        between = ->(row) { row.strip.empty? || (row.lstrip.start_with?("#") && row[/\A */].size <= last.start_column) }
        at -= 1 while at - 1 > last.start_line && between.(rows[at - 1])
      end
      (rows[0...at] + lines.map { |line| "#{line}\n" } + rows[at..].to_a).join
    end

    def entry_lines(name, label) = [ "- name: #{name}", "  label: #{scalar(label)}" ]

    # A label as written: plain when YAML reads it back as the same text,
    # else a double-quoted scalar (JSON's string, which YAML reads the same).
    def scalar(text)
      plain = begin
        YAML.safe_load("v: #{text}")&.fetch("v", nil)
      rescue Psych::Exception
        nil
      end
      plain == text && !text.include?("\n") ? text : JSON.generate(text)
    end

    def stub_for(kind, name)
      case kind
      when "section_style" then [ STYLESHEET, section_rule(name) ]
      when "page_template" then [ "views/#{Theme::Contract::PAGE_TEMPLATES}_#{name}.html.erb", page_template(name) ]
      end
    end

    def section_rule(name)
      existing = theme.join(STYLESHEET)
      lead = existing.file? && !existing.read.empty? ? (existing.read.end_with?("\n") ? "\n" : "\n\n") : ""
      <<~CSS.prepend(lead)
        /* The section style `#{name}` (theme.yml, section_styles), written by
           contentspiel generate. A section an editor gives this style carries
           this class beside its band's own. */
        .content-section--style-#{name} {
        }
      CSS
    end

    # The theme's own Standard template if it holds one, else the CMS's.
    def page_template(name)
      standard = "#{Theme::Contract::PAGE_TEMPLATES}_standard.html.erb"
      source = [ theme.join("views", standard), Rails.root.join("app/views", standard) ].find(&:file?)
      <<~ERB + source.read
        <%# The page template `#{name}` (theme.yml, page_templates), written by
            contentspiel generate as a copy of the Standard template below.
            Change it to draw a page of this template differently. %>
      ERB
    end

    # A file written whole goes to a hidden file beside it first and is
    # renamed onto its name (one step on the same file system), so an
    # interrupted write never leaves half a theme.yml or half a template.
    # The temporary file takes the mode the file had (or the umask's), as an
    # ordinary write would. The stylesheet's rule is appended: an append that
    # stops halfway leaves an unfinished rule at the end, which the check's
    # build names, and the author's text before it is untouched.
    def write(relative, content, append: false)
      file = theme.join(relative)
      file.dirname.mkpath
      return File.write(file, content, mode: "a") if append

      temporary = file.dirname.join(".#{file.basename}.#{Process.pid}.tmp")
      begin
        File.write(temporary, content)
        File.chmod(file.exist? ? file.stat.mode & 0o7777 : 0o666 & ~File.umask, temporary)
        File.rename(temporary, file)
      ensure
        FileUtils.rm_f(temporary)
      end
    end
  end
end
