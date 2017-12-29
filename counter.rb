#!/usr/bin/env -w ruby

# Gem supports colored text on many different consoles incl. Linux & Windows.
require 'pastel'

# (Found online.) Enables user to input command without pressing enter, which
# in turn is necessary if the screen is to be refreshed once per second.
module GetKey
  # Check if Win32API is accessible or not
  @use_stty = begin
    require 'Win32API'
    false
  rescue LoadError
    # Use Unix way
    true
  end

  # Return the ASCII code last key pressed, or nil if none
  #
  # Return::
  # * _Integer_: ASCII code of the last key pressed, or nil if none
  def self.getkey
    if @use_stty
      system('stty raw -echo') # => Raw mode, no echo
      char = (STDIN.read_nonblock(1).ord rescue nil)
      system('stty -raw echo') # => Reset terminal mode
      return char
    else
      return Win32API.new('crtdll', '_kbhit', [ ], 'I').Call.zero? ? nil : Win32API.new('crtdll', '_getch', [ ], 'L').Call
    end
  end
end

# Module above. Could separate from this file, but it's short enough.
include GetKey

# Helper, returns Time object for local time, stripping microseconds.
def time_now
  now = Time.new
  Time.new(now.year, now.month, now.day, now.hour, now.min, now.sec)
end


#####################################################################
# Runs app, displays prompt and interprets info, contains dispatch
# table, and organizes information from Dots and Stats classes.
class Counter
  attr_accessor :running, :paused, :dots
  def initialize
    @running = false    # Doesn't start running & compiling stats until 's'.
    @paused = true      # Determines how user input is used.
    @dots = Dots.new    # Compiles string with . # > <
    @stats = Stats.new  # Compiles stats that are displayed under prompt.
  end

  # The main method organizing the drawing of the app's visible components.
  def render
    while @running  # Begins at startup, ends with 'q', closing the program.
      system("clear") || system("cls")
      # Instructions and label on top.
      puts Pastel.new.black.on_yellow(
          "Counter | <Enter> to increment | <s>tart <p>ause <u>ndo <q>uit".ljust(69)
      )
      puts @dots.dots_string                      # Paints the dots.
      puts @stats.stats_string(@dots.dots_string) # Paints the stats.
      prompt                                      # Calls the prompt logic.
      sleep 1                                     # Repaints each second.
    end
  end

  # Displays prompt and listens for and dispatches user input.
  def prompt
    print "Command: "
    k = GetKey.getkey     # From the GetKey module above. Outputs numerical code.
    if k                  # 10 & 13 are space in ASCII & ANSI, 32 is enter.
                          # #chr translates to letter.
      k = ((k == 13 || k == 10 || k == 32) ? "#" : k.chr)
      puts k              # Show user his input.
    end
    record_user_input(k)  # Passes input to dispatch table for action.
  end

  # Dispatch table method; sends user input to appropriate method.
  def record_user_input(char)
    if char === 'q'                   # Quit.
      @running = false
    elsif char == '#' && ! @paused    # Add '#' to dots & increment count.
      @dots.add_count
      @stats.increment
    elsif char === 'p' && ! @paused   # Pause. Add '<' to dots.
      @paused = true                  # Used in this method.
      @dots.add_pause
    elsif char === 'u' && ! @paused   # Removes most recent '#' & updates count.
      undo_successful = @dots.undo_last
      @stats.decrement if undo_successful
    elsif /[ps]/ =~ char && @paused   # Start/unpause (the same). Add '>' to dots.
      @paused = false
      @dots.add_unpause
    elsif ! @paused                   # Add '.' and increment dot count (for avg).
      @dots.add_dot
      # Embarrassing kluge, if dot string is corrected due to slow processing,
      # so must be the stats dot count.
      if @dots.elapsed_correction > 0
        @stats.elapsed_correction(@dots.elapsed_correction)
        @dots.elapsed_correction = 0
      end
      @stats.increment_dots
    else                              # Script is @paused. Add ' ' to dots.
      @dots.add_empty
    end
  end
end

#####################################################################
# Prepares '*', "#", '.', '>', and '<', as well as times, all as part of a
# visual guide for the user to graphically illustrate the activity of the last
# ten minutes.
class Dots
  attr_accessor :dots_string, :elapsed_correction
  def initialize
    @dots_string = ''       # The important thing, the main item built.
    blank_string            # Initially populates @dots_string.
    @elapsed_correction = 0 # Insane super-kluge. Should be handled differently.
  end

  # Generate a string showing the last 10 minutes, mostly blanked out with '*'.
  # This recedes up out of the window as the counter runs. Makes it easier to
  # see when the user started.
  def blank_string
    # Calculate 9 minutes ago.
    prev = time_now - 540
    @dots_string += prev.strftime("%l:%M %P " + ("*" * 60))
    # Iterate 8 minutes, all blank (with '*').
    8.times do
      prev += 60 # 60 seconds.
      # Time#strftime format directives ensure consistent width.
      @dots_string += prev.strftime("\n%l:%M %P " + ("*" * 60))
    end
    # Calculate num seconds so far this minute.
    now = time_now
    secs_this_minute = now.sec.to_i
    # Append '*' minus one (= for the present, as yet unrecorded, second).
    @dots_string += now.strftime("\n%l:%M %P ") + ('*' * (secs_this_minute - 1) )
  end

  # Assorted necessary preparation done before the dots_string editing methods
  # are applied.
  def prelim_string_prep
    secs = time_now.sec
    fill_in_blanks_if_nec(secs) # Adds extra '.' and ' ' due to processing slowness.
    prep_new_line_if_nec(secs)  # Preps a new leader with time, when secs > 59.
  end

  # Add the leader (with the time) to the dots_string when the minute rolls over;
  # also, remove the oldest visible line.
  def start_new_line
    now = time_now
    leader = now.strftime("\n%l:%M %P ")  # Prep the leader.
    @dots_string += leader                # Add it to dots_string.
    @dots_string.sub!(/\A(.+?\n)/, "")    # Remove the oldest line (always 10).
  end

  # This corrects a mistake in dots_string in case of processing slowness.
  # Calculate what length should be since last \n. If short, and if last item
  # was '.' or ' ', then add more of the same to meet deficit. A kluge...if
  # the script were better maybe this wouldn't be necessary. Doesn't work
  # perfectly; not sure why not.
  def fill_in_blanks_if_nec(secs)
    /\n(.+?)\Z/.match(@dots_string) # Grab the last line.
    length_is = $&.length           # Length of that line (= $&).
    # Length of current line should be nine chars long (for '12:00 am ') plus
    # current seconds, minus 1 since the current second hasn't been recorded.
    length_should_be = secs == 0 ? 69 : 9 + secs - 1
    # If new line wasn't prepped, do so! This doesn't seem to work...?
    if length_is > 69 && (length_should_be == 10 ||
        length_should_be == 11) # && $&.scan(/#/).length > 0
      start_new_line
    end
    # Add ' ' or '.' when the length is less than it should be. Doesn't always work?
    if length_is < length_should_be
      if @dots_string[-1, 1] == " " # Handily grabs the last char of string.
        @dots_string += (" " * (length_should_be - length_is))
      end
      if @dots_string[-1, 1] == "."
        @dots_string +=  ("." * (length_should_be - length_is))
        @elapsed_correction += length_should_be - length_is
      end
    end
  end

  # Adds a new line when minute rolls over.
  # When secs this minute == 0, there should be 60 dots and no new line.
  # When secs this minute == 1, there should be 1 dot and a new line.
  def prep_new_line_if_nec(secs)
    if secs == 1
      start_new_line
    end
  end

  # DOTS STRING EDITING METHODS.
  # These come from the Counter#record_user_input dispatch table.
  # The dots_string editing methods mostly add one item to the string, and
  # otherwise leave it alone (except for an "undo" function). Note that this
  # is where prelim_string_prep is called.
  def add_count           # Add '#' to string.
    prelim_string_prep
    @dots_string += "#"
  end
  def add_pause           # Add '<' to string.
    prelim_string_prep
    @dots_string += "<"
  end
  def add_unpause         # Add '>' to string (on start and unpause).
    prelim_string_prep
    @dots_string += ">"
  end
  def undo_last           # Remove last '#' from string. Can be done repeatedly.
    # rindex handily finds the index of the last match in a string.
    index = @dots_string.rindex("#")
    if index
      @dots_string[index] = "."
    else
      false # Return false value so decrement doesn't happen.
    end
  end
  def add_dot             # Add a '.': counter is unpaused but not incremented.
    prelim_string_prep
    @dots_string += "."
  end
  def add_empty           # Add a ' ': counter is paused.
    prelim_string_prep
    @dots_string += " "
  end
end

#####################################################################
# Increments and decrements count & dot count, calculates elapsed time, and
# calculates other numbers and returns stats string for display to user.
class Stats
  attr_accessor :count, :dot_count
  def initialize
    @stats_string = ""
    @count = 0
    @dot_count = 0
  end

  # Stats editing methods.
  # Called by Counter#record_user_input at the same time as dots editing methods.
  def increment         # Add one to the count of whatever's being counted.
    @count += 1
  end

  def increment_dots    # Add one to the count of unpaused seconds w/o counts.
    @dot_count += 1
  end

  def decrement         # Both decrements the main count and increments dot count.
    @count -= 1         # Used if Dots#undo_last is successful.
    @dot_count += 1
  end

  # Returns number of unpaused seconds elapsed since beginning of session.
  def elapsed
    es = @count + @dot_count # es = elapsed seconds; omits starts and pauses.
    # Given seconds, return (as last processed line) a string in the form
    # "12:34", supporting single digits ("00:01"), etc.
    if es < 60
      es = "0" + es.to_s if es < 10
      "00:" + es.to_s
    else
      mins = (es / 60.0).to_i.to_s
      secs = (es % 60.0).to_i.to_s
      secs = "0" + secs.to_s if secs < 10
      mins + ":" + secs
    end
  end

  # Most dot (unpaused seconds without an increment) counts are done here in
  # the Stats class, but Stats#dot_count must be updated when processing
  # slowness forces extra dots to be added to the Dots string.
  def elapsed_correction(secs) # secs is passed from Dots via Counter (ugh).
    @dot_count += secs
  end

  # Prepare the stats string for display to user.
  def stats_string(dots_string)
    if @count > 0
      /(.{70})\Z/m.match(dots_string)           # Capture last 1:00 of string.
      last_minute_count = $&.scan(/#/).length   # Count the '#' instances.
      stats =
        (time_now.strftime("%l:%M:%S   ") +     # Current time w/ seconds.
        "Total: #{@count}      " +              # Total count.
        "Elapsed: #{elapsed}       " +          # Time elapsed in form "12:34".
        "Avg: #{sprintf("%5.2f",@count/         # Avg. count/min. from start.
          ((@count + @dot_count)/60.0))}     " +
        "Last: #{last_minute_count} ")          # Last minute count.
      return Pastel.new.black.on_yellow(stats)  # Pastel gem colorizes.
    end
  end

end

counter = Counter.new     # Initialize object that kicks it off.
counter.running = true    # When this is false, the program closes.
counter.render            # Counter#render is the enclosing loop of program.
puts "Bye!"               # Alerts user that program was ended with 'q'.
