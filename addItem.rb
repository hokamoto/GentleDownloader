#!/usr/bin/ruby
#coding:utf-8

require 'kyotocabinet'
include KyotoCabinet

require 'digest/md5'
require 'uri'
require 'pp'

$base_dir = File::dirname($0)
db = DB::new

# open the database
unless db.open("#{$base_dir}/add.kct", DB::OWRITER | DB::OCREATE)
  STDERR.printf("open error: %s\n", db.error)
end

# get the arguments
abort 'addItem.rb [URL] [output file/dir] (--nowait) (--uid uniqueID)' unless ARGV.count >= 2
arg_url = ARGV.shift
arg_output = ARGV.shift
arg_nowait = false
arg_uid = nil
while arg = ARGV.shift
  case arg
  when "--nowait"
    arg_nowait = true
  when "--uid"
    arg_uid = ARGV.shift
  end
end

# check arguments
url = nil
begin
  url = URI.parse(arg_url)
  raise URI::InvalidURIError if url.scheme == nil
rescue URI::InvalidURIError
  abort 'bad URL'
end
arg_uid = url.host if arg_uid == nil

dir = nil
filename = nil
arg_output = File.expand_path(arg_output)
if FileTest.directory?(arg_output) then
  dir = arg_output
else
  dir = File.dirname(arg_output)
  abort "no such output directory" unless FileTest.directory?(dir)
  filename = File.basename(arg_output)
end

filename = url.path.split('/').pop if filename == nil

# add a record
value = Hash.new
value['url'] = url
value['output'] = "#{dir}/#{filename}"
value['nowait'] = arg_nowait
value['uid'] = arg_uid

key = "#{Time.now.to_i.to_s}_#{Digest::MD5.hexdigest(url.path)}"

unless db.set(key, Marshal.dump(value))
  STDERR.printf("set error: %s\n", db.error)
end

# close the database
unless db.close
  STDERR.printf("close error: %s\n", db.error)
end

if value['nowait'] == true then
  puts "success (nowait)"
else
  puts "success"
end
