# #!/usr/bin/env -w ruby

require 'colorize'
require 'colorized_string'

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

include GetKey

# Helper; returns Time object for local time, stripping microseconds.
def time_now
  now = Time.new
  Time.new(now.year, now.month, now.day, now.hour, now.min, now.sec)
end


#####################################################################
class Counter
  attr_accessor :running, :paused, :dots
  def initialize
    @running = false
    @paused = true
    @dots = Dots.new
    @stats = Stats.new
  end

  def render
    while @running
      system("clear") || system("cls")
      puts @dots.dots_string
      puts @stats.stats_string(@dots.dots_string)
      prompt
      sleep 1
    end
  end

  # Displays prompt and listens for and dispatches input
  def prompt
    print "Command: "
    k = GetKey.getkey
    if k
      k = ((k == 13 || k == 32) ? "#" : k.chr)
      puts k
    end
    record_user_input(k)
  end

  def record_user_input(char)
    if char === 'q'
      @running = false
    elsif char == '#' && ! @paused
      @dots.add_count
      @stats.increment
    elsif char === 'p' && ! @paused
      @paused = true
      @dots.add_pause
    elsif /[ps]/ =~ char && @paused
      @paused = false
      @dots.add_unpause
    elsif ! @paused
      @dots.add_dot
      @stats.increment_dots
    elsif char == 'u'
      @dots.undo_last
      @stats.decrement
    else
      # If no action, save an "empty" second to @dots_string.
      @dots.add_empty
    end
  end
end

#####################################################################
class Dots
  attr_accessor :dots_string
  def initialize
    @dots_string = ''
    blank_string
    # NEXT: Replace the above with a blank string labeled with times only.
    # Will need a new method.
  end

  def blank_string
    # Calculate 9 minutes ago.
    prev = time_now - 540
    @dots_string += prev.strftime("%l:%M %P " + ("*" * 60))
    # Iterate 8 minutes.
    8.times do
      prev += 60
      @dots_string += prev.strftime("\n%l:%M %P " + ("*" * 60))
    end
    # Calculate num seconds so far this minute.
    now = time_now
    secs_this_minute = now.sec.to_i
    # Append '-' minus one.
    @dots_string += now.strftime("\n%l:%M %P ") + ('*' * secs_this_minute)
  end

  def prelim_string_prep
    secs = time_now.sec
    fill_in_blanks_if_nec(secs)
    prep_new_line_if_nec(secs)
  end

  def start_new_line
    now = time_now
    leader = now.strftime("\n%l:%M %P ")
    @dots_string += leader
    @dots_string.sub!(/\A(.+?\n)/, "")
  end

  # Calculate what length should be since last \n. If short, and if last item
  # was '.' or ' ', then add more of the same to meet deficit. A kluge...if
  # the script were better this wouldn't be necessary.
  def fill_in_blanks_if_nec(secs)
    /\n(.+?)\Z/.match(@dots_string)
    length_is = $&.length
    # Length of current line should be nine chars long (for '12:00 am ') plus
    # current seconds, minus 1 since the current second hasn't been recorded.
    length_should_be = secs == 0 ? 69 : 9 + secs - 1
    # If new line wasn't prepped, do so!
    if length_is > 68 && length_should_be == 10
      start_new_line
    end
    # Add ' ' or '.'
    if length_is < length_should_be
      @dots_string += " " if @dots_string[-1, 1] == " "
      @dots_string += "." if @dots_string[-1, 1] == "."
    end
  end

  def prep_new_line_if_nec(secs)
    if secs == 1
      start_new_line
    end
  end

  # The dots_string editing methods always add one item to the string, and
  # otherwise leave it alone (except for an "undo" function). First they deter-
  # mine if a new line is needed, and if so, calculate the time to place. They
  # also calculate if a space was skipped, and if so, they repeat the most
  # recent item IF it was '.' or ' '.
  def add_count
    prelim_string_prep
    @dots_string += "#"
  end
  def add_pause
    prelim_string_prep
    @dots_string += "<"
  end
  def add_unpause
    prelim_string_prep
    @dots_string += ">"
  end
  def add_dot
    prelim_string_prep
    @dots_string += "."
  end
  def add_empty
    prelim_string_prep
    @dots_string += " "
  end
end

#####################################################################
class Stats
  attr_accessor :count, :dot_count
  def initialize
    @stats_string = ""
    @count = 0
    @dot_count = 0
  end

  def increment
    @count += 1
  end

  def increment_dots
    @dot_count += 1
  end

  def decrement
    @count -= 1
    @dot_count += 1
  end

  def stats_string(dots_string)
    puts "yo!".black.on_light_yellow
    if @count > 0
      /(.{70})\Z/m.match(dots_string)
      last_minute_count = $&.scan(/#/).length
      (time_now.strftime("%l:%M:%S") +
      "         Total: #{@count}           " +
      "Avg: #{sprintf("%5.2f",@count/((@count + @dot_count)/60.0))}              " +
      "Last: #{last_minute_count}")
    end
  end

end

counter = Counter.new
counter.running = true
counter.render
puts "Bye!"
