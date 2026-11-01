class Theme
  # What a theme declares in `theme.yml`, at the top of its folder: three
  # lists of choices (`Theme::Contract::CHOICE_LISTS`), each entry a `name`
  # and a `label`, a page template also its `fields`, an icon its `file`.
  # The default theme declares its own in `config/theme/default.yml`; a theme
  # inherits a list it does not declare whole, and a list it declares
  # (an empty one too) replaces the default's.
  #
  # THE FILE IS DATA FROM OUTSIDE, SO NOTHING IN IT MAY RAISE. A value of the
  # wrong kind (`name: yes` is true, `name: 2` an Integer, `label:` with
  # nothing is nil, `fields: hero` is no list, an entry can be a String) is
  # one problem naming the list, the entry's place and the key, and the
  # entry is left out. `read` returns what could be read and the problems,
  # `Theme::Check` says the problems at the plain depth (they stop the boot,
  # and on a reload are kept as the theme's refusal), and `of` is only asked
  # of a folder that passed. Loaded with `safe_load` and no aliases: no
  # class, no symbol, no anchor.
  module Declarations
    FILE = "theme.yml".freeze
    DEFAULT_FILE = "config/theme/default.yml".freeze
    NAME = /\A[a-z][a-z0-9_]{0,39}\z/

    # The keys of an entry, per list.
    KEYS = {
      "section_styles" => %w[name label],
      "page_templates" => %w[name label fields],
      "icons" => %w[name label file]
    }.freeze

    module_function

    # [lists, problems]. `file` is how the problems name the source. `against`
    # is the default's lists, which an icon may name to take its file.
    def read(source, file: FILE, against: nil)
      against ||= default
      problems = []
      data = load_yaml(source, file, problems)
      return [ {}, problems ] if problems.any? || data.nil?

      unless data.is_a?(Hash)
        return [ {}, [ "#{file}: the file must be a mapping of lists (#{Contract::CHOICE_LISTS.join(", ")}), not #{kind(data)}. " \
                       "Write each list as a key followed by its entries." ] ]
      end

      lists = {}
      data.each do |key, entries|
        unless key.is_a?(String) && (Contract::CHOICE_LISTS.include?(key) || key == "settings")
          problems << "#{file}: `#{key}` is not a list a theme may declare: #{Contract::CHOICE_LISTS.join(", ")}. " \
                      "Rename it to one of them, or remove it."
          next
        end
        if key == "settings"
          problems << "#{file}: `settings` is not available. Appearance settings are not built yet. Remove it from #{file}."
          next
        end
        lists[key] = entries_of(key, entries, file, against, problems)
      end
      [ lists, problems ]
    end

    # The default theme's lists, read once per process from its file. A
    # problem in it is the CMS's own fault and stops the boot.
    def default
      @default ||= begin
        lists, problems = read(Rails.root.join(DEFAULT_FILE).read, file: DEFAULT_FILE, against: {})
        raise ArgumentError, "#{DEFAULT_FILE} is not sound: #{problems.join(" ")}" if problems.any?

        Contract::CHOICE_LISTS.index_with { |list| lists.fetch(list, []) }.freeze
      end
    end

    # The lists of a folder: its own where it declares them, the default's
    # for the rest.
    def of(folder)
      source = source_of(folder)
      return default if source.nil?

      default.merge(read(source).first)
    end

    def problems(folder)
      source = source_of(folder)
      source ? read(source).last : []
    end

    def source_of(folder)
      return nil unless folder.configured? && folder.declarations_file

      folder.read(FILE)
    end

    def load_yaml(source, file, problems)
      text = source.to_s.dup.force_encoding(Encoding::UTF_8)
      unless text.valid_encoding?
        problems << "#{file} is not UTF-8 text, so it cannot be read. Save the file as UTF-8."
        return nil
      end

      YAML.safe_load(text.delete_prefix("﻿"), permitted_classes: [], aliases: false, filename: file)
    rescue Psych::SyntaxError => error
      problems << "#{file}: line #{error.line} is not valid YAML (#{error.problem}). Correct it."
      nil
    rescue Psych::DisallowedClass, Psych::BadAlias => error
      problems << "#{file}: it uses a YAML alias, anchor or tag (#{error.message}), which a theme may not. " \
                  "Write the value out, with plain text, numbers and lists only."
      nil
    end

    def entries_of(list, entries, file, against, problems)
      unless entries.is_a?(Array)
        problems << "#{file}: #{list} must be a list of entries, not #{kind(entries)}. Write each entry as `- name: …` with a `label:`."
        return []
      end

      seen = []
      entries.each_with_index.filter_map do |entry, index|
        choice = entry_of(list, entry, index, file, against, seen, problems)
        seen << choice.name if choice
        choice
      end
    end

    def entry_of(list, entry, index, file, against, seen, problems)
      where = "#{file}: #{list}, entry #{index + 1}"
      unless entry.is_a?(Hash)
        problems << "#{where} must be a mapping with a `name` and a `label`, not #{kind(entry)}. Write it as `- name: …`."
        return nil
      end

      before = problems.size
      entry.each_key do |key|
        next if KEYS.fetch(list).include?(key)

        problems << "#{where}: `#{key}` is not a key of a #{list} entry: #{KEYS.fetch(list).join(", ")}. Remove it or correct the spelling."
      end

      name = entry["name"]
      if !name.is_a?(String)
        problems << "#{where}: `name` must be a text (a lowercase name such as services), not #{kind(name)}. Quote it if YAML reads it as something else."
        name = nil
      elsif !name.match?(NAME)
        problems << "#{where} (#{name}): `name` must be lowercase letters, digits and underscores, a letter first, at most 40. Rename it."
        name = nil
      elsif seen.include?(name)
        problems << "#{where} (#{name}): `name` is used by an earlier entry of #{list}. Give each entry a name of its own."
        name = nil
      end
      where += " (#{name})" if name

      labels = labels_of(entry["label"], where, problems)
      fields = fields_of(list, entry["fields"], where, problems)
      file_name, from = file_of(list, entry, name, against, where, problems)

      return nil if problems.size > before

      Choice.new(list: list, name: name, labels: labels, fields: fields, file: file_name, from: from)
    end

    def labels_of(label, where, problems)
      case label
      when String
        return { "en" => label } unless label.strip.empty?

        problems << "#{where}: `label` is empty. Say what a person sees in CS Studio."
      when Hash
        words = label.select { |key, value| key.is_a?(String) && value.is_a?(String) && !value.strip.empty? }
        return words if words.size == label.size && !label.empty?

        problems << "#{where}: `label` as a mapping must give each language code a text (en: Services), not #{kind(label)} with other keys or values. Correct it."
      when nil
        problems << "#{where}: `label` is missing. Add what a person sees in CS Studio, as a text or as a mapping of languages."
      else
        problems << "#{where}: `label` must be a text or a mapping of languages, not #{kind(label)}. Correct it."
      end
      nil
    end

    def fields_of(list, fields, where, problems)
      return [] unless list == "page_templates" && !fields.nil?

      unless fields.is_a?(Array)
        problems << "#{where}: `fields` must be a list (fields: [hero]), not #{kind(fields)}. Write it as a list."
        return []
      end
      bad = fields.reject { |field| field.is_a?(String) && Contract::PAGE_FIELDS.include?(field) }
      if bad.any?
        problems << "#{where}: `fields` may hold #{Contract::PAGE_FIELDS.join(", ")}, not #{bad.map { |field| kind(field) }.join(", ")}. Remove or correct it."
        return []
      end
      fields.uniq
    end

    # An icon's file, and whose it is. An entry that names one of the
    # default theme's icons and brings no file of its own is the default's.
    def file_of(list, entry, name, against, where, problems)
      return [ nil, :theme ] unless list == "icons"

      file = entry["file"]
      if file.nil?
        own = Array(against["icons"]).find { |icon| icon.name == name }
        return [ own.file, :default ] if own && name

        problems << "#{where}: `file` is missing. Name an SVG under assets/images, or use the name of one of the default theme's icons." if name
        return [ nil, :theme ]
      end
      return [ file, :theme ] if file.is_a?(String) && !file.strip.empty?

      problems << "#{where}: `file` must be a text, the SVG's path under assets/images, not #{kind(file)}. Correct it."
      [ nil, :theme ]
    end

    def kind(value)
      case value
      when nil then "empty"
      when String then "the text #{value.inspect}"
      when true, false then "the truth value #{value}"
      when Integer, Float then "the number #{value}"
      when Array then "a list"
      when Hash then "a mapping"
      else "a #{value.class.name.downcase}"
      end
    end
  end
end
