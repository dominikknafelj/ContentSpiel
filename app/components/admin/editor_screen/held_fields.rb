module Admin
  module EditorScreen
    # Makes the fields of a form someone else holds read-only (live-editing
    # spec §4.3, handoff 5 to 7): a text control is `readonly`, so its text
    # stays selectable and at full contrast, and a control HTML cannot make
    # read-only (a select, a checkbox, a radio, a file input, a button) is
    # `disabled`. Hidden fields are left alone, so the form still carries the
    # same names and values as the editable one.
    #
    # ONE PASS OVER THE RENDERED FORM, here, rather than a read-only option on
    # each of the eight components that draw a field: a field component added
    # later is covered the day it is rendered in an editor, and the editable
    # and the held form cannot drift apart (the component tests compare every
    # control's name and value, and everything else of its markup). The
    # browser's counterpart, for the one form that turns read-only in place,
    # is `editing/freeze`, which reads `rules` below.
    #
    # WHAT THE PARSE KEEPS AND WHAT IT DOES NOT. Parsed with the HTML5
    # parser and written out again, the markup keeps its entities, its
    # attributes' order, `<template>` and `<script type="application/json">`
    # contents, SVG and boolean attributes (`hidden` becomes `hidden=""`, the
    # same attribute). The one thing the round trip loses is a newline at the
    # start of a `textarea`, `pre` or `listing`: the parser drops the first
    # one (the spec says so) and the serializer does not put it back, so a
    # value that began with a newline would lose it in the browser. That is
    # put back here before writing.
    #
    # ACTIONS ARE AN ALLOW-LIST. Every `data-action` token on every element
    # of a held form (a `div` or a `ul` as much as a control, with a
    # `@window` or `@document` target, with `:stop` or `:once` options or a
    # key filter on the event) is removed unless the controller action it
    # names is in `allowed_actions` (the CMS's four and each block type's
    # declared `read_only_actions`): the ones that only read or only move
    # focus. A writing action added to a field next year is therefore dead in
    # a held form from the day it is written, and `held_fields_test.rb`
    # keeps its OWN list of what may survive, so a new survivor fails it until
    # someone decides. A control that only READS (a `details`, a link) has no
    # action to lose. The strip's "Copy my text" is outside the form.
    #
    # CONTROL KINDS (`READONLY_TYPES`, `HIDDEN_TYPES`): a text control
    # takes `readonly`; `hidden` is left alone; EVERYTHING ELSE (checkbox,
    # radio, file, range, color, every kind of button, an `input` of a type
    # this list has never heard of, a select) is `disabled`.
    module HeldFields
      # Input types `readonly` applies to (HTML's list), and a missing type, which is text.
      READONLY_TYPES = %w[text search tel url email password number date datetime-local month week time].freeze
      HIDDEN_TYPES = %w[hidden].freeze
      # `identifier#method` of the CMS's own actions that survive: reading, or
      # moving focus. A block type's own are its definition's
      # `read_only_actions` (block types spec, decision 10), reviewed with
      # the type.
      CMS_ACTIONS = %w[
        admin--editor--slug-preview#update
        admin--rich-text--editor#containFocus
        admin--ui--menu#select
        admin--ui--menu#close
      ].freeze
      # THE TRANSITION (block types plan, Task 8 deletes it): the Code type's
      # counter, until the type declares it.
      WRITTEN_TYPE_ACTIONS = %w[admin--editor--code-limit#update].freeze

      # Every action that survives in a held form: the CMS's, and each
      # registered block type's declared ones.
      def self.allowed_actions = (CMS_ACTIONS + WRITTEN_TYPE_ACTIONS + ::BlockTypes.all.flat_map(&:read_only_actions)).uniq.freeze

      # The rules as data, for the browser's counterpart (`editing/freeze`),
      # which turns ONE form read-only in place: the region renders this into
      # the page (`LiveRegionComponent`), so the script and this module read
      # one source and the lists are written once.
      def self.rules = { allowed_actions: allowed_actions, readonly_types: READONLY_TYPES, hidden_types: HIDDEN_TYPES }

      GUARD = '<button type="submit" disabled hidden tabindex="-1" data-held-guard></button>'.freeze
      NEWLINE_FIRST = "textarea, pre, listing".freeze

      module_function

      # `guard: true` puts a disabled submit button first in the markup: a form
      # whose default button is disabled does not submit when Enter is pressed
      # in a field (HTML's implicit submission), and a form with one text
      # field and no button would. The held form has no autosave to catch it.
      def call(html, guard: false)
        fragment = Nokogiri::HTML5.fragment("#{GUARD if guard}#{html}")
        fragment.css("textarea").each { |field| field["readonly"] = "readonly" }
        fragment.css("input").each { |field| restrict_input(field) }
        fragment.css("select, button").each { |field| field["disabled"] = "disabled" }
        allowed = allowed_actions
        fragment.css("[data-action]").each { |element| keep_allowed_actions(element, allowed) }
        fragment.css(NEWLINE_FIRST).each { |element| keep_first_newline(element) }
        fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety -- markup this app has just rendered, parsed and written out again
      end

      def restrict_input(field)
        type = (field["type"] || "text").strip.downcase
        if HIDDEN_TYPES.include?(type) then nil
        elsif READONLY_TYPES.include?(type) then field["readonly"] = "readonly"
        else field["disabled"] = "disabled"
        end
      end

      # `click:stop->admin--x#go:once@window` is `admin--x#go`: the event with
      # its filters and options before the arrow, the action's own options and
      # the target after the method.
      def action_of(token)
        body = token.sub(/\A[^>]*->/, "")
        body.sub(/@\w+\z/, "").sub(/(?::!?\w+)+\z/, "")
      end

      def keep_allowed_actions(element, allowed)
        kept = element["data-action"].split.select { |token| allowed.include?(action_of(token)) }
        kept.empty? ? element.remove_attribute("data-action") : element["data-action"] = kept.join(" ")
      end

      def keep_first_newline(element)
        first = element.children.first
        first.content = "\n#{first.content}" if first&.text? && first.content.start_with?("\n")
      end
    end
  end
end
