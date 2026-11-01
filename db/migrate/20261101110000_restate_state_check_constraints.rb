# Rewrites two check constraints so `db/schema.rb` dumps them the same on every
# Postgres version. `state IN ('a', 'b')` is stored as an array of varchar
# literals whose casts different versions print differently, which made a plain
# `db:migrate` rewrite the dump with formatting changes only. Text literals
# against a text-cast column have no cast left to print differently.
class RestateStateCheckConstraints < ActiveRecord::Migration[8.1]
  CONSTRAINTS = {
    note_threads: [ "note_threads_state", "open", "resolved" ],
    presence_marks: [ "presence_marks_state_known", "here", "away" ]
  }.freeze

  def up
    CONSTRAINTS.each do |table, (name, first, second)|
      remove_check_constraint table, name: name
      add_check_constraint table, "state::text = ANY (ARRAY['#{first}'::text, '#{second}'::text])", name: name
    end
  end

  def down
    CONSTRAINTS.each do |table, (name, first, second)|
      remove_check_constraint table, name: name
      add_check_constraint table, "state IN ('#{first}', '#{second}')", name: name
    end
  end
end
