module Admin
  module EditorScreen
    # The line under a date-and-time field that says which time zone it is
    # read in: the SITE's, never the browser's (every CS Studio request runs
    # inside `Time.use_zone(site zone)`, and `Admin::Scheduling` parses the
    # value there). For the Schedule dialog and the publish dialog's "At a
    # time".
    module SiteZoneLine
      # "Berlin time (GMT+1), the site’s time zone." -- one string (admin copy
      # is one sentence per string). The offset is the one in force at `time`
      # (the time shown in the field), so a summer schedule reads GMT+2.
      def site_zone_line(time)
        offset = gmt_offset(time.utc_offset)
        name = Current.site.effective_time_zone.name
        if name.include?("(")
          "#{name}, #{offset}, the site’s time zone."   # no nested parentheses
        elsif name.match?(/time|\AUTC\z/i)
          "#{name} (#{offset}), the site’s time zone."
        else
          "#{name} time (#{offset}), the site’s time zone."
        end
      end

      private

      def gmt_offset(seconds)
        sign = seconds.negative? ? "-" : "+"
        hours, minutes = (seconds.abs / 60).divmod(60)
        "GMT#{sign}#{hours}#{":%02d" % minutes if minutes.positive?}"
      end
    end
  end
end
