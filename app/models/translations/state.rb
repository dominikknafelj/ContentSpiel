module Translations
  # One stored row of `translation_states` (see `Translations::StateIndex`,
  # the only thing that writes it).
  class State < ApplicationRecord
    self.table_name = "translation_states"
  end
end
