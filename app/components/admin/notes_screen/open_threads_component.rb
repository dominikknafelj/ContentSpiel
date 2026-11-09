module Admin
  module NotesScreen
    # The Notes screen's rail of open threads: the records the viewer may read
    # that have unresolved notes, the most recently active first
    # (`Dashboard::OpenThreads`, the data Waiting for you draws as its own
    # list), at most the rows it was given, then how many more lie on other
    # pages, as a line and no link: there is no fuller list to go to. With no
    # rows it keeps the rail and says so.
    #
    # It is information, not a filter, so it follows the list in the document
    # (`.admin-list-rail__rail`, which the lists' grid docks in the second
    # column and sticks): docked it is the rail's ground, below the threshold a
    # card after the list. Its name is its heading.
    class OpenThreadsComponent < Admin::AdminComponent
      def initialize(threads:)
        @threads = threads
      end

      private

      attr_reader :threads

      def rows = threads.rows

      def more = threads.more_records
    end
  end
end
