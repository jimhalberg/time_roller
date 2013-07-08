require 'rubygems'
require 'fastercsv'
require 'fileutils'

#### RUN DIRECTIONS:
#
# 1. Create a new directory next to time_roller.rb, probably with a name that indicates when you're going to run (let's say "2013-07-08-10AM")
# 2. Export the timesheet csvs and put them inside that directory.  Name the csvs such that they retain the person's name, but no longer have spaces
# 3. Run like this: ruby time_roller.rb "2013-07-08-10AM"
# 4. Checkout your run results in the csv that was just created in 2013-07-08-10AM/processed/

COLUMN_NAMES = {
  :primary_bucket => 'primary bucket',
  :total_time => 'total time (h:mm)',
  :date => 'date'
}

@sheets = Hash.new{ |h,filename| h[filename] = Hash.new{ |h, a_date| h[a_date] = Hash.new{ |h, primary_bucket| h[primary_bucket] = 0 }}}

def main
  puts "It's processing time time!"

  setup_source_files

  @filenames.each do |filename|
    @filename = filename
    handle_file
  end
  sheet_category_report
end

def setup_source_files
  @directory_for_run = ARGV[0].to_s
  if @directory_for_run.length == 0
    raise "You need to give a directory name as an argument."

  elsif File.directory?(@directory_for_run)
    @filenames = Dir.glob("#{ @directory_for_run }/*.csv")
    if @filenames.length == 0
      raise "No source files found at: #{ File.dirname(__FILE__) }/#{ @directory_for_run }/*"
    end

  else
    raise "Could not find directory: #{ File.dirname(__FILE__) }/#{ @directory_for_run }"
  end
end

def handle_file
  puts; puts "&&&&&&&& #{ @filename }"
  FasterCSV.foreach(@filename, :headers => :first_row) do |row|
    if valid_row?(row)
      accumulate(row)
    end
  end
end

def valid_row?(row)
  answers = [ COLUMN_NAMES[:date], COLUMN_NAMES[:total_time], COLUMN_NAMES[:primary_bucket]].collect { |required_column| row[required_column].to_s == '' || row[required_column].to_s == '0:00' }
  if answers.include?(true) # something is not valid
    if answers.include?(false) # if they were all true, this thing is invalid to the point of just ignoring
      puts "!! invalid row: #{ row.inspect }"
    end
    return false
  else
    return true
  end
end

# expected format HH:MM
def minutes(total_time)
  hours, minutes = total_time.split(':')
  return minutes.to_i + hours.to_i*60
end

def hours_minutes(minutes)
  hours = (minutes / 60).floor
  return "#{ hours }h:#{ minutes - hours * 60 }m"
end

def accumulate(row)
  @sheets[@filename][row[COLUMN_NAMES[:date]]][row[COLUMN_NAMES[:primary_bucket]].strip] += minutes(row[COLUMN_NAMES[:total_time]])
end

# +a_date expected to be format: mm/dd/yyyy
def timeframe(a_date)
  a_date =~ /(\d{1,2})\/(\d{1,2})\/(\d{4})/
  return "#{ $3 }-#{ $1 }-#{ $2.to_i < 15 ? '1 to 15' : '15 to end' }"
end

def cell_time(primary_bucket_hash, primary_bucket, time_bucket)
  if primary_bucket_hash.has_key?(primary_bucket)
    return primary_bucket_hash[primary_bucket][time_bucket] || 0
  else
    return 0
  end
end

# name should either be what you already want it to be, or a path to a csv
def formatted_name(name)
  if name =~ /csv/
    return name.split('/').last.split('.').first
  else
    return name
  end
end

def sheet_category_rollup
  @rollup = Hash.new{ |h, filename| h[filename] = Hash.new{ |h, primary_bucket| h[primary_bucket] = Hash.new{ |h, timeframe| h[timeframe] = 0 }}}
  @time_buckets = []
  @primary_buckets = []
  @sheet_timeframe = Hash.new{ |h, filename| h[filename] = Hash.new{ |h, timeframe| h[timeframe] = 0 }}
  @sheets.each do |filename, dates_hash|
    dates_hash.each do |a_date, primary_buckets_hash|
      primary_buckets_hash.each do |primary_bucket, total_time|
        a_timeframe = timeframe(a_date)
        @time_buckets << a_timeframe
        @primary_buckets << primary_bucket
        @sheet_timeframe[filename][a_timeframe] += total_time
        @sheet_timeframe[:team_without_jim][a_timeframe] += total_time unless filename =~ /Jim/
        @rollup[filename][primary_bucket][a_timeframe] += total_time
        @rollup[:team_without_jim][primary_bucket][a_timeframe] += total_time unless filename =~ /Jim/
      end
      @time_buckets = @time_buckets.uniq.sort
      @primary_buckets = @primary_buckets.uniq.sort
    end
  end
end

def sheet_category_report
  sheet_category_rollup
puts "trying to create: #{ @directory_for_run }/processed"
  FileUtils.mkdir_p("#{ @directory_for_run }/processed") unless File.directory?("#{ @directory_for_run }/processed")
  FasterCSV.open("#{ @directory_for_run }/processed/#{ Time.now.strftime("%Y-%m-%d %H-%M") }.csv", "w") do |output_csv|

    @rollup.each do |name, primary_bucket_hash|
      output_csv << [ formatted_name(name) ] + @time_buckets.collect{ |tb| [ tb, '%' ] }.flatten + [ 'Overall', '%' ] # section header row
      @primary_buckets.each do |primary_bucket|
        minutes = [ ]
        total = 0
        @time_buckets.each do |time_bucket|
          minutes_for_cell = cell_time(primary_bucket_hash, primary_bucket, time_bucket)
          total += minutes_for_cell
          minutes << [ time_bucket, minutes_for_cell ]
        end
        # output_csv << [ primary_bucket ] + minutes.collect{ |mins_array| [ hours_minutes(mins_array[1]), @sheet_timeframe[name][mins_array[0]] ] }.flatten + [ hours_minutes(total), 'total % here' ]
        output_csv << [ primary_bucket ] + minutes.collect{ |mins_array| [ hours_minutes(mins_array[1]), "#{ sprintf('%.2f', mins_array[1].to_f / @sheet_timeframe[name][mins_array[0]] * 100) }%" ] }.flatten + [ hours_minutes(total), "#{ sprintf('%.2f', total.to_f / @sheet_timeframe[name].values.inject{ |sum, x| sum + x } * 100) }%" ]
      end

      output_csv << []
    end

  end
end

main
