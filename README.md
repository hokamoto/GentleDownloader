GentleDownloader
================

A server-friendly downloader implemented with Ruby

GentleDownloader has throttling mechanism so that it will cause neither overload problems nor performance issues on remote machines.


Install
---------------
You should install the following libraries as prerequisite to GentleDownloader.

* [Log4r](http://log4r.rubyforge.org/)
* [Kyoto Cabinet](http://fallabs.com/kyotocabinet/spex.html)

How to use GentleDownloader
---------------
Start GentleDownloader.

    # ./downloader.rb

GentleDownloader will start as a daemon.

Push a download item to GentleDownloader.

    # ./addItem.rb [URL] [output] (--nowait) (--uid uniqueID)

+   `URL` :
    A URL that you want to download

+   `output` :
    Specify file or directory that GentleDownloader stores the file to

+   `(optional) --nowait` :
    Specify the option if you do not want GentleDownloader to wait

+   `(optional) --uid uniqueID` :
    GentleDownloader restrains intensive accesses with the host of URL in default. If you specify _uniqueID_, GentleDownloader will treat all URL that has same _uniqueID_ as a same host.

Tuning
---------------
GentleDownloader does not access a same host within 15 seconds in default. You can change the value by modifying download.rb.

```ruby
INTERVAL = 15
```

Troubleshooting
---------------
If GentleDownloader cannot download any files, remove box.kct and add.kct and restart GentleDownloader.
This step will reset the download queue.
