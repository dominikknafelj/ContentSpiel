module SiteSearch
  # The state of one backend's index (search spec §6.6): one row per
  # backend, written by the background build alone.
  class IndexState < ApplicationRecord
    self.table_name = "search_index_states"
  end
end
