require 'time'

module Google

  #
  # Represents a Google Event.
  #
  # === Attributes
  #
  # * +id+ - The google assigned id of the event (nil until saved). Read only.
  # * +title+ - The title of the event. Read Write.
  # * +description+ - The content of the event. Read Write.
  # * +location+ - The location of the event. Read Write.
  # * +start_time+ - The start time of the event (Time object, defaults to now). Read Write.
  # * +end_time+ - The end time of the event (Time object, defaults to one hour from now).  Read Write.
  # * +calendar+ - What calendar the event belongs to. Read Write.
  # * +all_day + - Does the event run all day. Read Write.
  # * +quickadd+ - A string that Google parses when setting up a new event.  If set and then saved it will take priority over any attributes you have set. Read Write.
  # * +reminders+ - A hash containing reminders. Read Write.
  # * +attendees+ - An array of hashes containing information about attendees. Read Write
  # * +transparency+ - Does the event 'block out space' on the calendar.  Valid values are true, false or 'transparent', 'opaque'. Read Write.
  # * +duration+ - The duration of the event in seconds. Read only.
  # * +html_link+ - An absolute link to this event in the Google Calendar Web UI. Read only.
  # * +raw+ - The full google json representation of the event. Read only.
  #
  class Event
    attr_reader :id, :raw, :html_link
    attr_accessor :title, :location, :calendar, :quickadd, :transparency, :attendees, :description, :reminders

    #
    # Create a new event, and optionally set it's attributes.
    #
    # ==== Example
    #
    # event = Google::Event.new
    # event.calendar = AnInstanceOfGoogleCalendaer
    # event.start_time = Time.now
    # event.end_time = Time.now + (60 * 60)
    # event.title = "Go Swimming"
    # event.description = "The polar bear plunge"
    # event.location = "In the arctic ocean"
    # event.transparency = "opaque"
    # event.reminders = { 'useDefault'  => false, 'overrides' => ['minutes' => 10, 'method' => "popup"]}
    # event.attendees = [
    #                     {'email' => 'some.a.one@gmail.com', 'displayName' => 'Some A One', 'responseStatus' => 'tentative'},
    #                     {'email' => 'some.b.one@gmail.com', 'displayName' => 'Some B One', 'responseStatus' => 'tentative'}
    #                   ]
    #
    def initialize(params = {})
      [:id, :raw, :html_link, 
       :title, :location, :calendar, :quickadd, :attendees, :description, :reminders, :start_time, :end_time,  ].each do |attribute|
        instance_variable_set("@#{attribute}", params[attribute])
      end

      self.transparency = params[:transparency]
      self.all_day      = params[:all_day] if params[:all_day]
    end

    #
    # Sets the start time of the Event.  Must be a Time object or a parse-able string representation of a time.
    #
    def start_time=(time)
      @start_time = parse_time(time)
    end

    #
    # Get the start_time of the event.
    #
    # If no time is set (i.e. new event) it defaults to the current time.
    #
    def start_time
      @start_time ||= Time.now.utc
      (@start_time.is_a? String) ? @start_time : @start_time.xmlschema
    end

    #
    # Get the end_time of the event.
    #
    # If no time is set (i.e. new event) it defaults to one hour in the future.
    #
    def end_time
      @end_time ||= Time.now.utc + (60 * 60) # seconds * min
      (@end_time.is_a? String) ? @end_time : @end_time.xmlschema
    end

    #
    # Sets the end time of the Event.  Must be a Time object or a parse-able string representation of a time.
    #
    def end_time=(time)
      @end_time = parse_time(time)
      raise ArgumentError, "End Time must be either Time or String" unless (time.is_a?(String) || time.is_a?(Time))
      @end_time = (time.is_a? String) ? Time.parse(time) : time.dup.utc
    end

    #
    # Returns whether the Event is an all-day event, based on whether the event starts at the beginning and ends at the end of the day.
    #
    def all_day?
      time = (@start_time.is_a?  String) ? Time.parse(@start_time) : @start_time.dup.utc
      duration % (24 * 60 * 60) == 0 && time == Time.local(time.year,time.month,time.day)
    end

    #
    # Makes an event all day, by setting it's start time to the passed in time and it's end time 24 hours later.
    # Note: this will clobber both the start and end times currently set.
    #
    def all_day=(time)
      if time.class == String
        time = Time.parse(time)
      end
      @start_time = time.strftime("%Y-%m-%d")
      @end_time = (time + 24*60*60).strftime("%Y-%m-%d")
    end

    #
    # Duration of the event in seconds
    #
    def duration
      Time.parse(end_time) - Time.parse(start_time)
    end

    #
    # Stores reminders for this event. Multiple reminders are allowed.
    #
    # Examples
    #  
    # event = cal.create_event do |e|
    #   e.title = 'Some Event'
    #   e.start_time = Time.now + (60 * 10)
    #   e.end_time = Time.now + (60 * 60) # seconds * min
    #   e.reminders = { 'useDefault'  => false, 'overrides' => [{method: 'email', minutes: 4}, {method: 'popup', minutes: 60}, {method: 'sms', minutes: 30}]} 
    # end
    # 
    # event = Event.new :start_time => "2012-03-31", :end_time => "2012-04-03", :reminders => { 'useDefault'  => false, 'overrides' => [{'minutes' => 10, 'method' => "popup"}]}
    #
    def reminders
      @reminders ||= {}
    end

    # 
    # Utility method that simplifies setting the transparency of an event.
    # You can pass true or false.  Defaults to transparent.
    #
    def transparency=(val)
      if val == false || val.to_s.downcase == 'opaque'
        @transparency = 'opaque'
      else
        @transparency = 'transparent'
      end
    end

    #
    # Returns true if the event is transparent otherwise returns false.
    # Transparent events do not block time on a calendar.
    #
    def transparent?
      @transparency == "transparent"
    end

    #
    # Returns true if the event is opaque otherwise returns false.
    # Opaque events block time on a calendar.
    # 
    def opaque?
      @transparency == "opaque"
    end

    #
    # Convenience method used to build an array of events from a Google feed.
    #
    def self.build_from_google_feed(response, calendar)
      events = response['items'] ? response['items'] : [response]
      events.collect {|e| new_from_feed(e, calendar)}.flatten
    end

    #
    # Google JSON representation of an event object.
    #
    def to_json
      "{
        \"summary\": \"#{title}\",
        \"description\": \"#{description}\", 
        \"location\": \"#{location}\", 
        \"start\": {
          \"dateTime\": \"#{start_time}\"
        },
        \"end\": {
          \"dateTime\": \"#{end_time}\"
        },
        #{attendees_json}
        \"reminders\": {
          #{reminders_json}
        }
      }"
    end
    
    #
    # JSON representation of attendees
    #
    def attendees_json
      return unless @attendees

      attendees = @attendees.map do |attendee|
        "{
          \"displayName\": \"#{attendee['displayName']}\", 
          \"email\": \"#{attendee['email']}\",
          \"responseStatus\": \"#{attendee['responseStatus']}\"
        }"
      end.join(",\n")

      "\"attendees\": [\n#{attendees}],"
    end

    #
    # JSON representation of a reminder
    #
    def reminders_json
      if reminders && reminders.is_a?(Hash) && reminders['overrides'] 
        overrides = reminders['overrides'].map do |reminder|
          "{
            \"method\": \"#{reminder['method']}\", 
            \"minutes\": #{reminder['minutes']}
          }"
        end.join(",\n")
        "\n\"useDefault\": false,\n\"overrides\": [\n#{overrides}]"
      else
        "\"useDefault\": true"
      end
    end

    #
    # String representation of an event object.
    #
    def to_s
      "Event Id '#{self.id}'\n\tTitle: #{title}\n\tStarts: #{start_time}\n\tEnds: #{end_time}\n\tLocation: #{location}\n\tDescription: #{description}\n\n"
    end

    #
    # Saves an event.
    #  Note: make sure to set the calendar before calling this method.
    #
    def save
      update_after_save(@calendar.save_event(self))
    end

    #
    # Deletes an event.
    #  Note: If using this on an event you created without using a calendar object,
    #  make sure to set the calendar before calling this method.
    #
    def delete
      @calendar.delete_event(self)
      @id = nil
    end

    #
    # Returns true if the event will use quickadd when it is saved.
    #
    def use_quickadd?
      quickadd && id == nil
    end

    #
    # Returns true if this a new event.
    #
    def new_event?
      id == nil || id == ''
    end

    protected

    #
    # Create a new event from a google 'entry'
    #
    def self.new_from_feed(e, calendar) #:nodoc:
      Event.new(:id           => e['id'],
                :calendar     => calendar,
                :raw          => e,
                :title        => e['summary'],
                :description  => e['description'],
                :location     => e['location'],
                :start_time   => (e['start'] ? e['start']['dateTime'] : ''),
                :end_time     => (e['end']   ? e['end']['dateTime'] : ''),
                :transparency => e['transparency'],
                :html_link    => e['htmlLink'],
                :updated      => e['updated'],
                :reminders    => e['reminders'],
                :attendees    => e['attendees'] )

    end

    #
    # Set the ID after google assigns it (only necessary when we are creating a new event)
    #
    def update_after_save(respose) #:nodoc:
      return if @id && @id != ''
      @raw = JSON.parse(respose.body)
      @id = @raw['id']
      @html_link = @raw['htmlLink']
    end

    #
    # A utility method used centralize time parsing.
    #
    def parse_time(time) #:nodoc
      raise ArgumentError, "Start Time must be either Time or String" unless (time.is_a?(String) || time.is_a?(Time))
      (time.is_a? String) ? Time.parse(time) : time.dup.utc
    end

  end
end
