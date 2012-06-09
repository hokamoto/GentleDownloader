#!/usr/bin/ruby
#coding:utf-8

require 'kyotocabinet'
include KyotoCabinet

require 'digest/md5'
require 'uri'
require 'net/http'
Net::HTTP.version_1_2
require 'pp'
require 'digest/md5'

require 'log4r'
include Log4r

require "thread"

# daemonize
Process.daemon(true)

# preparing logger
formatter = Log4r::PatternFormatter.new(
  :pattern => "%d %C[%l]: %M",
  :date_format => "%Y/%m/%d %H:%M:%S"
)
@logger = Log4r::Logger.new('download')
@logger.trace = true
@logger.level = INFO
outputter = Log4r::FileOutputter.new(
  "file",
  :filename => '/var/log/downloader.log',
  :trunc => false,
  :formatter => formatter
)
@logger.add(outputter)

@locker = Mutex::new

# USER_AGENT = "Mozilla/4.0 (compatible; MSIE 6.0; Windows XP)"
ACCEPT_LANGUAGE = "ja"
TIMEOUT = 20

MAX_THREADS = 10
INTERVAL = 15
DB_SYNC_INTERVAL = 30
DB_LOAD_INTERVAL = 5

$base_dir = File::dirname($0)

@threads = Array.new(MAX_THREADS)
@db = DB::new
@limiter = DB::new

def sync_db  
  if @limiter.get("DB_LOAD") == nil or (Time.now - Marshal.load(@limiter.get("DB_LOAD"))).truncate > DB_LOAD_INTERVAL then
    # load new entries
    db_add = DB::new
    unless db_add.open("#{$base_dir}/add.kct", DB::OWRITER | DB::OCREATE)
      STDERR.printf("open error: %s\n", db_add.error)
    end
    count = 0
    db_add.each { |key, value|
      @db.set(key, value)
      count += 1
    }
    db_add.clear
    unless db_add.close
      STDERR.printf("close error: %s\n", db_add.error)
    end
    @logger.info "#{count.to_s} entries were added" if count > 0
    
    @limiter.set("DB_LOAD", Marshal.dump(Time.now))
  end
  
  if @limiter.get("DB_SYNC") == nil or (Time.now - Marshal.load(@limiter.get("DB_SYNC"))).truncate > DB_SYNC_INTERVAL then
    # sync
    @logger.debug "sync in-memory db to persistent db"
    db_persistent = DB::new
    unless db_persistent.open("#{$base_dir}/box.kct", DB::OWRITER | DB::OCREATE | DB::OTRUNCATE)
      STDERR.printf("open error: %s\n", db_persistent.error)
    end    
    
    @db.each { |key, value|
      db_persistent.set(key, value)
    }
    
    unless db_persistent.close
      STDERR.printf("close error: %s\n", db_persistent.error)
    end
    
    @limiter.set("DB_SYNC", Marshal.dump(Time.now))   
    @logger.debug "done"
  else            
    sleep 1.0 / 100.0
  end
end

# open the database
unless @db.open("%", DB::OWRITER | DB::OCREATE)
  STDERR.printf("open error: %s\n", @db.error)
end
unless @limiter.open("-", DB::OWRITER | DB::OCREATE)
  STDERR.printf("open error: %s\n", @limiter.error)
end

# copy persistent db to in-memory db
@logger.info "copy persistent db to in-memory db"
db_persistent = DB::new
unless db_persistent.open("#{$base_dir}/box.kct", DB::OWRITER | DB::OCREATE)
  STDERR.printf("open error: %s\n", db_persistent.error)
end

db_persistent.each { |key, value|
  @db.set(key, value)
}
@db.synchronize
unless db_persistent.close
  STDERR.printf("close error: %s\n", db_persistent.error)
end

@logger.info "done"
sync_db

MAX_THREADS.times do |i|
  @threads[i] = Thread.new(i) do |param|    
    loop do

      isDownload = false
      isNoWait = false
      url = nil
      output = nil
      nowait = nil
      uid = nil
      
      @locker.synchronize do
        # check
        (key, tmp) = @db.shift
        if key == nil then
          # sync in-memory db and persistent db
          sync_db
          # @logger.info "no data to process. wait 1 sec."
          sleep 1
          next  
        end
        value = Marshal.load(tmp)
        url = value['url']
        output = value['output']
        nowait = value['nowait']
        uid = value['uid']

        if @limiter.get(url.host) == nil or (Time.now - Marshal.load(@limiter.get(uid))).truncate > INTERVAL or nowait == true then 
          @limiter.set(uid, Marshal.dump(Time.now))
          isDownload = true
          isNoWait = true if nowait == true
        else
          key = "#{Time.now.to_i.to_s}_#{Digest::MD5.hexdigest(url.path)}"

          unless @db.set(key, tmp)
            STDERR.printf("set error: %s\n", @db.error)
          end
          
          # sync in-memory db and persistent db
          sync_db
        end
      end
      
      if isDownload == true then
        # download
        if isNoWait == true then
          @logger.info "#{i})download (nowait): #{url.to_s}"
        else
          @logger.info "#{i})download: #{url.to_s}"
        end        

        Net::HTTP.start(url.host, url.port) { |http|
          http.read_timeout = TIMEOUT
          response = http.get(url.path, { 'User-Agent'      => USER_AGENT,
              'Accept-Language' => ACCEPT_LANGUAGE} )

          if response.code == '200' then
            begin
              open(output, "wb") { |f|
                f.puts response.body
              }
              @logger.info "#{i})done #{url.to_s}"
            rescue
              @logger.info "#{i})invalid output file #{url.to_s}"
            end
          elsif response.code == '301' or response.code == '302' or response.code == '303' or response.code == '307' then
            if response["location"].index("http") != nil then
              # moved
              url2 = URI.parse(response["location"])
              
              Net::HTTP.start(url2.host, url2.port) { |http|
                http.read_timeout = TIMEOUT
                response = http.get(url2.path, { 'User-Agent'      => USER_AGENT,
                    'Accept-Language' => ACCEPT_LANGUAGE} )
                
                if response.code == '200' then
                  begin
                    open(output, "wb") { |f|
                      f.puts response.body
                    }
                    @logger.info "#{i})done(moved) #{url.to_s}"
                  rescue
                    @logger.info "#{i})invalid output file #{url.to_s}"
                  end
                end
              }
            end
          else
            @logger.info "error: #{response.code} (#{url.to_s})"
          end
        }
      end
    end
  end
end

# join the threads
MAX_THREADS.times { |i|
  @threads[i].join
}

# close the database
unless @db.close
  STDERR.printf("close error: %s\n", @db.error)
end
unless @limiter.close
  STDERR.printf("close error: %s\n", @limiter.error)
end